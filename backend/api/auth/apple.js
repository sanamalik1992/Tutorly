import { createRemoteJWKSet, jwtVerify } from 'jose'
import supabase from '../../lib/supabase.js'
import { signToken } from '../../lib/jwt.js'
import { handleCors } from '../../lib/cors.js'
import { sessionLimits, sessionsTodayCount } from '../../lib/user.js'

const APPLE_JWKS = createRemoteJWKSet(
  new URL('https://appleid.apple.com/auth/keys')
)

export default async function handler(req, res) {
  if (handleCors(req, res)) return
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' })

  try {
    const { identityToken, fullName } = req.body
    if (!identityToken) return res.status(400).json({ error: 'identityToken required' })

    // Verify Apple-issued JWT against Apple's public keys
    const { payload } = await jwtVerify(identityToken, APPLE_JWKS, {
      issuer:   'https://appleid.apple.com',
      audience: process.env.APPLE_BUNDLE_ID,
    })

    const appleUserId = payload.sub
    const email = payload.email ?? null
    const name  = (fullName?.trim()) || email?.split('@')[0] || 'Student'

    // Upsert user — preserve is_pro on subsequent logins
    const { data: user, error } = await supabase
      .from('tutorly_users')
      .upsert(
        { id: appleUserId, email, name, updated_at: new Date().toISOString() },
        { onConflict: 'id', ignoreDuplicates: false }
      )
      .select()
      .single()

    if (error) throw error

    const count = await sessionsTodayCount(appleUserId)
    const { dailySessions } = sessionLimits(user.is_pro)
    const jwt = await signToken({ sub: appleUserId })

    return res.json({
      jwt,
      user: {
        id:                user.id,
        name:              user.name,
        email:             user.email,
        isPro:             user.is_pro,
        sessionsRemaining: Math.max(0, dailySessions - count),
        secondsToday:      0,
      },
    })
  } catch (err) {
    console.error('[auth/apple]', err)
    return res.status(401).json({ error: 'Authentication failed' })
  }
}

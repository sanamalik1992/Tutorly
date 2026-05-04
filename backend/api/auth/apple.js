import { createRemoteJWKSet, jwtVerify } from 'jose'
import { upsertUser, sessionsToday, limits } from '../../lib/user.js'
import { signToken } from '../../lib/jwt.js'
import { handleCors } from '../../lib/cors.js'

const APPLE_JWKS = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'))

export default async function handler(req, res) {
  if (handleCors(req, res)) return
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' })

  try {
    const { identityToken, fullName } = req.body ?? {}
    if (!identityToken) return res.status(400).json({ error: 'identityToken required' })

    const { payload } = await jwtVerify(identityToken, APPLE_JWKS, {
      issuer:   'https://appleid.apple.com',
      audience: process.env.APPLE_BUNDLE_ID,
    })

    const user  = await upsertUser({ id: payload.sub, email: payload.email ?? null, name: fullName?.trim() || null })
    const count = await sessionsToday(user.id)
    const { daily } = limits(user.isPro)
    const jwt   = await signToken({ sub: user.id })

    return res.json({
      jwt,
      user: {
        id:                user.id,
        name:              user.name,
        email:             user.email,
        isPro:             user.isPro,
        sessionsRemaining: Math.max(0, daily - count),
        secondsToday:      0,
      },
    })
  } catch (err) {
    console.error('[auth/apple]', err)
    return res.status(401).json({ error: 'Authentication failed' })
  }
}

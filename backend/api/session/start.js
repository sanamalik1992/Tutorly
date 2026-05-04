import supabase from '../../lib/supabase.js'
import { handleCors, requireAuth } from '../../lib/cors.js'
import { getUser, sessionsTodayCount, sessionLimits } from '../../lib/user.js'

async function getEphemeralToken() {
  const res = await fetch('https://api.openai.com/v1/realtime/sessions', {
    method:  'POST',
    headers: {
      Authorization:  `Bearer ${process.env.OPENAI_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ model: 'gpt-4o-realtime-preview' }),
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`OpenAI ${res.status}: ${text}`)
  }
  const data = await res.json()
  return data.client_secret?.value ?? null
}

export default async function handler(req, res) {
  if (handleCors(req, res)) return
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' })

  const payload = await requireAuth(req, res)
  if (!payload) return

  try {
    const userId = payload.sub
    const user   = await getUser(userId)
    const count  = await sessionsTodayCount(userId)
    const { dailySessions, sessionSecs } = sessionLimits(user.is_pro)

    if (count >= dailySessions) {
      return res.status(402).json({
        error:   'Daily session limit reached',
        message: user.is_pro
          ? 'You have used all your sessions for today.'
          : 'Free limit reached. Upgrade to Pro for more sessions.',
      })
    }

    const ephemeralToken = await getEphemeralToken()
    if (!ephemeralToken) throw new Error('Empty ephemeral token from OpenAI')

    // Record the session
    await supabase.from('tutorly_sessions').insert({
      user_id:    userId,
      started_at: new Date().toISOString(),
    })

    return res.json({
      ephemeralToken,
      sessionLimitSeconds: sessionSecs,
      sessionsRemaining:   Math.max(0, dailySessions - count - 1),
    })
  } catch (err) {
    console.error('[session/start]', err)
    return res.status(500).json({ error: 'Failed to start session' })
  }
}

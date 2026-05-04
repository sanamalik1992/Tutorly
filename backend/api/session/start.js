import { handleCors, requireAuth } from '../../lib/cors.js'
import { getUser, sessionsToday, incrementSessionsToday, startSession, limits } from '../../lib/user.js'

async function mintEphemeralToken() {
  const r = await fetch('https://api.openai.com/v1/realtime/sessions', {
    method:  'POST',
    headers: {
      Authorization:  `Bearer ${process.env.OPENAI_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ model: 'gpt-4o-realtime-preview' }),
  })
  if (!r.ok) throw new Error(`OpenAI ${r.status}: ${await r.text()}`)
  const data = await r.json()
  const token = data.client_secret?.value
  if (!token) throw new Error('No client_secret in OpenAI response')
  return token
}

export default async function handler(req, res) {
  if (handleCors(req, res)) return
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' })

  const payload = await requireAuth(req, res)
  if (!payload) return

  try {
    const userId = payload.sub
    const user   = await getUser(userId)
    const count  = await sessionsToday(userId)
    const { daily, secs } = limits(user.isPro)

    if (count >= daily) {
      return res.status(402).json({
        error:   'Daily session limit reached',
        message: user.isPro
          ? 'You have used all your sessions for today.'
          : 'Free limit reached. Upgrade to Pro for more sessions.',
      })
    }

    const ephemeralToken = await mintEphemeralToken()

    await incrementSessionsToday(userId)
    await startSession(userId)

    return res.json({
      ephemeralToken,
      sessionLimitSeconds: secs,
      sessionsRemaining:   Math.max(0, daily - count - 1),
    })
  } catch (err) {
    console.error('[session/start]', err)
    return res.status(500).json({ error: 'Failed to start session' })
  }
}

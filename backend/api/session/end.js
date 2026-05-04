import { handleCors, requireAuth } from '../../lib/cors.js'
import { endSession } from '../../lib/user.js'

export default async function handler(req, res) {
  if (handleCors(req, res)) return
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' })

  const payload = await requireAuth(req, res)
  if (!payload) return

  try {
    await endSession(payload.sub, Number(req.body?.secondsUsed ?? 0))
    return res.json({ ok: true })
  } catch (err) {
    console.error('[session/end]', err)
    return res.status(500).json({ error: 'Failed to end session' })
  }
}

import { handleCors, requireAuth } from '../../lib/cors.js'
import { userResponse } from '../../lib/user.js'

export default async function handler(req, res) {
  if (handleCors(req, res)) return
  if (req.method !== 'GET') return res.status(405).json({ error: 'Method not allowed' })

  const payload = await requireAuth(req, res)
  if (!payload) return

  try {
    return res.json(await userResponse(payload.sub))
  } catch (err) {
    console.error('[user/me]', err)
    return res.status(401).json({ error: 'User not found' })
  }
}

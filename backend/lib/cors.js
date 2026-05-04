export function handleCors(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*')
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS')
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type,Authorization')
  if (req.method === 'OPTIONS') { res.status(200).end(); return true }
  return false
}

export async function requireAuth(req, res) {
  const { verifyToken } = await import('./jwt.js')
  const raw = req.headers.authorization ?? ''
  const token = raw.startsWith('Bearer ') ? raw.slice(7) : raw
  if (!token) { res.status(401).json({ error: 'Unauthorized' }); return null }
  try {
    return await verifyToken(token)
  } catch {
    res.status(401).json({ error: 'Unauthorized' })
    return null
  }
}

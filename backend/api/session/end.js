import supabase from '../../lib/supabase.js'
import { handleCors, requireAuth } from '../../lib/cors.js'

export default async function handler(req, res) {
  if (handleCors(req, res)) return
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' })

  const payload = await requireAuth(req, res)
  if (!payload) return

  try {
    const userId      = payload.sub
    const secondsUsed = Number(req.body?.secondsUsed ?? 0)

    // Close the most recent open session for this user
    const { data: session } = await supabase
      .from('tutorly_sessions')
      .select('id')
      .eq('user_id', userId)
      .is('ended_at', null)
      .order('started_at', { ascending: false })
      .limit(1)
      .maybeSingle()

    if (session) {
      await supabase
        .from('tutorly_sessions')
        .update({ ended_at: new Date().toISOString(), seconds_used: secondsUsed })
        .eq('id', session.id)
    }

    return res.json({ ok: true })
  } catch (err) {
    console.error('[session/end]', err)
    return res.status(500).json({ error: 'Failed to end session' })
  }
}

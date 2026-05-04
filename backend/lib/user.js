import supabase from './supabase.js'

const FREE_DAILY_SESSIONS  = 1
const PRO_DAILY_SESSIONS   = 5
const FREE_SESSION_SECS    = 5 * 60    // 5 minutes
const PRO_SESSION_SECS     = 20 * 60   // 20 minutes

export async function getUser(userId) {
  const { data, error } = await supabase
    .from('tutorly_users')
    .select('*')
    .eq('id', userId)
    .single()
  if (error) throw error
  return data
}

export async function sessionsTodayCount(userId) {
  const todayStart = new Date()
  todayStart.setHours(0, 0, 0, 0)
  const { count } = await supabase
    .from('tutorly_sessions')
    .select('*', { count: 'exact', head: true })
    .eq('user_id', userId)
    .gte('started_at', todayStart.toISOString())
  return count ?? 0
}

export function sessionLimits(isPro) {
  return {
    dailySessions: isPro ? PRO_DAILY_SESSIONS : FREE_DAILY_SESSIONS,
    sessionSecs:   isPro ? PRO_SESSION_SECS   : FREE_SESSION_SECS,
  }
}

export async function userResponse(userId) {
  const user  = await getUser(userId)
  const count = await sessionsTodayCount(userId)
  const { dailySessions } = sessionLimits(user.is_pro)
  return {
    id:                user.id,
    name:              user.name,
    email:             user.email,
    isPro:             user.is_pro,
    sessionsRemaining: Math.max(0, dailySessions - count),
    secondsToday:      0,
  }
}

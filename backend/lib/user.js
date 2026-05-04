import redis from './redis.js'

// ── limits ──────────────────────────────────────────────────────────────────
const FREE_DAILY   = 1
const PRO_DAILY    = 5
const FREE_SECS    = 5  * 60   // 5 min
const PRO_SECS     = 20 * 60   // 20 min

// ── keys ─────────────────────────────────────────────────────────────────────
const userKey          = id   => `user:${id}`
const dailyKey         = (id) => `sessions_today:${id}:${today()}`
const activeSessionKey = id   => `session:active:${id}`
const sessionKey       = id   => `session:${id}`

function today() {
  return new Date().toISOString().slice(0, 10)
}

// ── user CRUD ─────────────────────────────────────────────────────────────────
export async function getUser(id) {
  const u = await redis.get(userKey(id))
  if (!u) throw new Error(`User ${id} not found`)
  return typeof u === 'string' ? JSON.parse(u) : u
}

export async function upsertUser({ id, email, name }) {
  const existing = await redis.get(userKey(id))
  const prev = existing
    ? (typeof existing === 'string' ? JSON.parse(existing) : existing)
    : null
  const user = {
    id,
    email:     email ?? prev?.email ?? null,
    name:      name  ?? prev?.name  ?? 'Student',
    isPro:     prev?.isPro ?? false,
    createdAt: prev?.createdAt ?? new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  }
  await redis.set(userKey(id), JSON.stringify(user))
  return user
}

export async function setUserPro(id) {
  const user = await getUser(id)
  user.isPro = true
  user.updatedAt = new Date().toISOString()
  await redis.set(userKey(id), JSON.stringify(user))
  return user
}

// ── session counting ──────────────────────────────────────────────────────────
export async function sessionsToday(userId) {
  const n = await redis.get(dailyKey(userId))
  return Number(n ?? 0)
}

export async function incrementSessionsToday(userId) {
  const key = dailyKey(userId)
  await redis.incr(key)
  await redis.expire(key, 60 * 60 * 48) // auto-expire after 48 h
}

// ── session tracking ──────────────────────────────────────────────────────────
export async function startSession(userId) {
  const id = crypto.randomUUID()
  const session = { id, userId, startedAt: new Date().toISOString(), endedAt: null, secondsUsed: 0 }
  await redis.set(sessionKey(id), JSON.stringify(session))
  await redis.set(activeSessionKey(userId), id)
  return session
}

export async function endSession(userId, secondsUsed) {
  const id = await redis.get(activeSessionKey(userId))
  if (!id) return
  const raw = await redis.get(sessionKey(id))
  if (!raw) return
  const session = typeof raw === 'string' ? JSON.parse(raw) : raw
  session.endedAt     = new Date().toISOString()
  session.secondsUsed = secondsUsed
  await redis.set(sessionKey(id), JSON.stringify(session))
  await redis.del(activeSessionKey(userId))
}

// ── limits helper ─────────────────────────────────────────────────────────────
export function limits(isPro) {
  return { daily: isPro ? PRO_DAILY : FREE_DAILY, secs: isPro ? PRO_SECS : FREE_SECS }
}

export async function userResponse(userId) {
  const user  = await getUser(userId)
  const count = await sessionsToday(userId)
  const { daily } = limits(user.isPro)
  return {
    id:                user.id,
    name:              user.name,
    email:             user.email,
    isPro:             user.isPro,
    sessionsRemaining: Math.max(0, daily - count),
    secondsToday:      0,
  }
}

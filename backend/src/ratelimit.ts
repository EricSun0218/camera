export type Bucket = { remaining: number; resetAt: number }
export type TakeResult =
  | { ok: true; remaining: number }
  | { ok: false; retryAfterSec: number }

export async function take(
  kv: KVNamespace,
  ip: string,
  route: 'coach' | 'grade',
  capacity: number,
  windowMs: number,
): Promise<TakeResult> {
  const key = `rl:${route}:${ip}`
  const now = Date.now()
  const raw = await kv.get(key, 'json') as Bucket | null

  let bucket: Bucket
  if (!raw || raw.resetAt <= now) {
    bucket = { remaining: capacity, resetAt: now + windowMs }
  } else {
    bucket = raw
  }

  if (bucket.remaining <= 0) {
    return { ok: false, retryAfterSec: Math.max(1, Math.ceil((bucket.resetAt - now) / 1000)) }
  }

  bucket.remaining -= 1
  await kv.put(key, JSON.stringify(bucket), { expirationTtl: Math.ceil(windowMs / 1000) + 60 })
  return { ok: true, remaining: bucket.remaining }
}

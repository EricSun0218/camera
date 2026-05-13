import { describe, it, expect } from 'vitest'
import { env } from 'cloudflare:test'
import { take } from '../src/ratelimit'

describe('rate limiter', () => {
  it('first call passes for given ip+route', async () => {
    const r = await take(env.RATELIMIT, '1.1.1.1', 'coach', 30, 3600_000)
    expect(r.ok).toBe(true)
    expect(r.remaining).toBe(29)
  })

  it('depletes after N calls', async () => {
    const ip = '2.2.2.2'
    for (let i = 0; i < 30; i++) await take(env.RATELIMIT, ip, 'coach', 30, 3600_000)
    const r = await take(env.RATELIMIT, ip, 'coach', 30, 3600_000)
    expect(r.ok).toBe(false)
    expect(r.retryAfterSec).toBeGreaterThan(0)
  })

  it('routes are independent', async () => {
    const ip = '3.3.3.3'
    for (let i = 0; i < 10; i++) await take(env.RATELIMIT, ip, 'grade', 10, 3600_000)
    const grade = await take(env.RATELIMIT, ip, 'grade', 10, 3600_000)
    const coach = await take(env.RATELIMIT, ip, 'coach', 30, 3600_000)
    expect(grade.ok).toBe(false)
    expect(coach.ok).toBe(true)
  })
})

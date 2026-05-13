import { describe, it, expect, vi, beforeEach } from 'vitest'
import { env, SELF } from 'cloudflare:test'
import * as anthropicModule from '../src/anthropic'

// fake call
const fakeCoach = { tip: 'step left', priority: 'med' as const }
const fakeGrade = {
  scene: 'portrait', lighting: 'golden_hour', rationale: 'warm',
  grade: {
    exposure_ev: 0.1, contrast: 5, highlights: -20, shadows: 15, whites: 0, blacks: -5,
    saturation: 0, vibrance: 10, temperature: 5, tint: 0,
    hsl: {
      red:{hue:0,saturation:-5,luminance:0}, orange:{hue:0,saturation:0,luminance:0},
      yellow:{hue:0,saturation:0,luminance:0}, green:{hue:0,saturation:0,luminance:0},
      aqua:{hue:0,saturation:0,luminance:0}, blue:{hue:0,saturation:0,luminance:0},
      purple:{hue:0,saturation:0,luminance:0}, magenta:{hue:0,saturation:0,luminance:0},
    },
    vignette_intensity: 0, vignette_radius: 1,
  },
}

beforeEach(() => {
  vi.restoreAllMocks()
})

describe('routes', () => {
  it('GET / returns hello', async () => {
    const r = await SELF.fetch('https://x/')
    expect(r.status).toBe(200)
  })

  it('POST /coach returns parsed tip', async () => {
    vi.spyOn(anthropicModule, 'callClaudeVision').mockResolvedValue(fakeCoach)
    const r = await SELF.fetch('https://x/coach', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'cf-connecting-ip': '9.9.9.1' },
      body: JSON.stringify({ image_b64: 'xx', client_version: '1.0.0' }),
    })
    expect(r.status).toBe(200)
    expect(await r.json()).toEqual(fakeCoach)
  })

  it('POST /grade returns parsed scene analysis', async () => {
    vi.spyOn(anthropicModule, 'callClaudeVision').mockResolvedValue(fakeGrade)
    const r = await SELF.fetch('https://x/grade', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'cf-connecting-ip': '9.9.9.2' },
      body: JSON.stringify({ image_b64: 'xx', client_version: '1.0.0' }),
    })
    expect(r.status).toBe(200)
    const body = await r.json() as any
    expect(body.scene).toBe('portrait')
  })

  it('POST /coach rate-limits after 30 calls', async () => {
    vi.spyOn(anthropicModule, 'callClaudeVision').mockResolvedValue(fakeCoach)
    const ip = '9.9.9.3'
    for (let i = 0; i < 30; i++) {
      await SELF.fetch('https://x/coach', {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'cf-connecting-ip': ip },
        body: JSON.stringify({ image_b64: 'xx' }),
      })
    }
    const r = await SELF.fetch('https://x/coach', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'cf-connecting-ip': ip },
      body: JSON.stringify({ image_b64: 'xx' }),
    })
    expect(r.status).toBe(429)
    expect(r.headers.get('retry-after')).not.toBeNull()
  })

  it('rejects bad body', async () => {
    const r = await SELF.fetch('https://x/coach', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'cf-connecting-ip': '9.9.9.4' },
      body: JSON.stringify({}),
    })
    expect(r.status).toBe(400)
  })

  it('falls back to neutral grade if Claude returns invalid JSON shape', async () => {
    vi.spyOn(anthropicModule, 'callClaudeVision').mockResolvedValue({ totally: 'wrong' })
    const r = await SELF.fetch('https://x/grade', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'cf-connecting-ip': '9.9.9.5' },
      body: JSON.stringify({ image_b64: 'xx' }),
    })
    expect(r.status).toBe(200)
    const body = await r.json() as any
    expect(body.scene).toBe('other')
    expect(body.grade.exposure_ev).toBe(0)
  })
})

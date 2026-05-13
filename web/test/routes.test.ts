import { describe, it, expect, vi, beforeEach } from 'vitest'

vi.mock('@/lib/anthropic', () => ({
  callClaudeVision: vi.fn(),
  makeAnthropic: vi.fn(() => ({})),
}))

import * as anthropicModule from '@/lib/anthropic'
import { POST as coachPOST } from '@/app/api/coach/route'
import { POST as gradePOST } from '@/app/api/grade/route'

const fakeCoach = { tip: 'step left', priority: 'med' as const }
const fakeGrade = {
  scene: 'portrait', lighting: 'golden_hour', rationale: 'warm',
  grade: {
    exposure_ev: 0.1, contrast: 5, highlights: -20, shadows: 15, whites: 0, blacks: -5,
    saturation: 0, vibrance: 10, temperature: 5, tint: 0,
    hsl: {
      red:    { hue: 0, saturation: -5, luminance: 0 },
      orange: { hue: 0, saturation: 0,  luminance: 0 },
      yellow: { hue: 0, saturation: 0,  luminance: 0 },
      green:  { hue: 0, saturation: 0,  luminance: 0 },
      aqua:   { hue: 0, saturation: 0,  luminance: 0 },
      blue:   { hue: 0, saturation: 0,  luminance: 0 },
      purple: { hue: 0, saturation: 0,  luminance: 0 },
      magenta:{ hue: 0, saturation: 0,  luminance: 0 },
    },
    vignette_intensity: 0, vignette_radius: 1,
  },
}

function makeReq(path: string, body: object) {
  return new Request(`http://x${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  })
}

beforeEach(() => {
  process.env.ANTHROPIC_API_KEY = 'test'
  vi.clearAllMocks()
})

describe('/api/coach', () => {
  it('returns parsed tip', async () => {
    vi.mocked(anthropicModule.callClaudeVision).mockResolvedValue(fakeCoach)
    const res = await coachPOST(makeReq('/api/coach', { image_b64: 'xx', client_version: '1.0.0' }))
    expect(res.status).toBe(200)
    expect(await res.json()).toEqual(fakeCoach)
  })

  it('rejects empty body', async () => {
    const res = await coachPOST(makeReq('/api/coach', {}))
    expect(res.status).toBe(400)
  })

  it('returns silent on bad shape', async () => {
    vi.mocked(anthropicModule.callClaudeVision).mockResolvedValue({ wrong: true })
    const res = await coachPOST(makeReq('/api/coach', { image_b64: 'xx' }))
    expect(res.status).toBe(200)
    const body = await res.json() as any
    expect(body.tip).toBeNull()
    expect(body.priority).toBe('low')
  })

  it('returns silent on thrown error', async () => {
    vi.mocked(anthropicModule.callClaudeVision).mockRejectedValue(new Error('boom'))
    const res = await coachPOST(makeReq('/api/coach', { image_b64: 'xx' }))
    expect(res.status).toBe(200)
    const body = await res.json() as any
    expect(body.tip).toBeNull()
  })
})

describe('/api/grade', () => {
  it('returns parsed scene analysis', async () => {
    vi.mocked(anthropicModule.callClaudeVision).mockResolvedValue(fakeGrade)
    const res = await gradePOST(makeReq('/api/grade', { image_b64: 'xx', client_version: '1.0.0' }))
    expect(res.status).toBe(200)
    const body = await res.json() as any
    expect(body.scene).toBe('portrait')
  })

  it('rejects empty body', async () => {
    const res = await gradePOST(makeReq('/api/grade', {}))
    expect(res.status).toBe(400)
  })

  it('falls back to neutral grade on bad shape', async () => {
    vi.mocked(anthropicModule.callClaudeVision).mockResolvedValue({ totally: 'wrong' })
    const res = await gradePOST(makeReq('/api/grade', { image_b64: 'xx' }))
    expect(res.status).toBe(200)
    const body = await res.json() as any
    expect(body.scene).toBe('other')
    expect(body.grade.exposure_ev).toBe(0)
  })

  it('falls back to neutral grade on thrown error', async () => {
    vi.mocked(anthropicModule.callClaudeVision).mockRejectedValue(new Error('boom'))
    const res = await gradePOST(makeReq('/api/grade', { image_b64: 'xx' }))
    expect(res.status).toBe(200)
    const body = await res.json() as any
    expect(body.scene).toBe('other')
    expect(body.lighting).toBe('mixed')
  })
})

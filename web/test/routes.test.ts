import { describe, it, expect, vi, beforeEach } from 'vitest'

vi.mock('@/lib/llm', () => ({
  callVision: vi.fn(),
  makeLLM: vi.fn(() => ({})),
  llmConfig: vi.fn(() => ({
    apiKey: 'test-key',
    baseURL: 'https://mock/v1',
    model: 'test-model',
  })),
}))

import * as llmModule from '@/lib/llm'
import { POST as guidancePOST } from '@/app/api/guidance/route'
import { POST as gradePOST } from '@/app/api/grade/route'

const fakePersonGuidance = {
  subject_type: 'person' as const,
  pose_id: 'stand',
  pose_x: 0.67, pose_y: 0.55, pose_height: 0.72,
  suggested_zoom: 1.5,
}

const fakeSceneGuidance = {
  subject_type: 'scene' as const,
  target_x: 0.5, target_y: 0.55, target_w: 0.7, target_h: 0.5,
  suggested_zoom: 1.8,
}

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
  vi.clearAllMocks()
  vi.mocked(llmModule.llmConfig).mockReturnValue({
    apiKey: 'test-key', baseURL: 'https://mock/v1', model: 'test-model',
  })
})

describe('/api/guidance', () => {
  it('returns parsed person guidance', async () => {
    vi.mocked(llmModule.callVision).mockResolvedValue(fakePersonGuidance)
    const res = await guidancePOST(makeReq('/api/guidance', { image_b64: 'xx' }))
    expect(res.status).toBe(200)
    const body = await res.json() as any
    expect(body.subject_type).toBe('person')
    expect(body.pose_id).toBe('stand')
  })

  it('returns parsed scene guidance', async () => {
    vi.mocked(llmModule.callVision).mockResolvedValue(fakeSceneGuidance)
    const res = await guidancePOST(makeReq('/api/guidance', { image_b64: 'xx' }))
    expect(res.status).toBe(200)
    const body = await res.json() as any
    expect(body.subject_type).toBe('scene')
    expect(body.target_w).toBe(0.7)
  })

  it('rejects empty body', async () => {
    const res = await guidancePOST(makeReq('/api/guidance', {}))
    expect(res.status).toBe(400)
  })

  it('returns empty fallback on bad shape', async () => {
    vi.mocked(llmModule.callVision).mockResolvedValue({ wrong: true })
    const res = await guidancePOST(makeReq('/api/guidance', { image_b64: 'xx' }))
    expect(res.status).toBe(200)
    const body = await res.json() as any
    expect(body.subject_type).toBe('empty')
  })

  it('returns empty fallback on thrown error with degraded flag', async () => {
    vi.mocked(llmModule.callVision).mockRejectedValue(new Error('boom'))
    const res = await guidancePOST(makeReq('/api/guidance', { image_b64: 'xx' }))
    expect(res.status).toBe(200)
    const body = await res.json() as any
    expect(body.subject_type).toBe('empty')
    expect(body.degraded).toBe(true)
  })

  it('schema-reject empty fallback is NOT degraded', async () => {
    vi.mocked(llmModule.callVision).mockResolvedValue({ wrong: true })
    const res = await guidancePOST(makeReq('/api/guidance', { image_b64: 'xx' }))
    const body = await res.json() as any
    expect(body.subject_type).toBe('empty')
    expect(body.degraded).toBeUndefined()
  })

  it('coerces incomplete person guidance (missing pose fields) to empty', async () => {
    vi.mocked(llmModule.callVision).mockResolvedValue({
      subject_type: 'person', suggested_zoom: 1,
    })
    const res = await guidancePOST(makeReq('/api/guidance', { image_b64: 'xx' }))
    const body = await res.json() as any
    expect(body.subject_type).toBe('empty')
    expect(body.degraded).toBeUndefined()
  })

  it('coerces incomplete scene guidance (missing target fields) to empty', async () => {
    vi.mocked(llmModule.callVision).mockResolvedValue({
      subject_type: 'scene', target_x: 0.5, suggested_zoom: 1,
    })
    const res = await guidancePOST(makeReq('/api/guidance', { image_b64: 'xx' }))
    const body = await res.json() as any
    expect(body.subject_type).toBe('empty')
  })

  it('500s when env not configured', async () => {
    vi.mocked(llmModule.llmConfig).mockReturnValue(null)
    const res = await guidancePOST(makeReq('/api/guidance', { image_b64: 'xx' }))
    expect(res.status).toBe(500)
  })
})

describe('/api/grade', () => {
  it('returns parsed scene analysis', async () => {
    vi.mocked(llmModule.callVision).mockResolvedValue(fakeGrade)
    const res = await gradePOST(makeReq('/api/grade', { image_b64: 'xx' }))
    expect(res.status).toBe(200)
    const body = await res.json() as any
    expect(body.scene).toBe('portrait')
  })

  it('rejects empty body', async () => {
    const res = await gradePOST(makeReq('/api/grade', {}))
    expect(res.status).toBe(400)
  })

  it('falls back to neutral grade on bad shape', async () => {
    vi.mocked(llmModule.callVision).mockResolvedValue({ totally: 'wrong' })
    const res = await gradePOST(makeReq('/api/grade', { image_b64: 'xx' }))
    expect(res.status).toBe(200)
    const body = await res.json() as any
    expect(body.scene).toBe('other')
    expect(body.grade.exposure_ev).toBe(0)
  })

  it('falls back to neutral grade on thrown error with degraded flag', async () => {
    vi.mocked(llmModule.callVision).mockRejectedValue(new Error('boom'))
    const res = await gradePOST(makeReq('/api/grade', { image_b64: 'xx' }))
    expect(res.status).toBe(200)
    const body = await res.json() as any
    expect(body.scene).toBe('other')
    expect(body.degraded).toBe(true)
  })

  it('flags degraded on schema-reject fallback', async () => {
    vi.mocked(llmModule.callVision).mockResolvedValue({ totally: 'wrong' })
    const res = await gradePOST(makeReq('/api/grade', { image_b64: 'xx' }))
    const body = await res.json() as any
    expect(body.scene).toBe('other')
    expect(body.degraded).toBe(true)
  })
})

// On-demand AI composition guidance. One call per "AI 指导" button tap on iOS.
// No rate limiting in v1; add Upstash if abuse appears.
import { NextResponse } from 'next/server'
import { z } from 'zod'
import { AIGuidanceSchema } from '@/lib/schemas'
import { COMPOSITION_SKILL } from '@/lib/composition-skill'
import { callVision, makeLLM, llmConfig } from '@/lib/llm'

export const runtime = 'nodejs'
export const maxDuration = 60
export const preferredRegion = ['hkg1']

const RequestBody = z.object({
  image_b64: z.string().min(1).max(2_000_000),
  client_version: z.string().optional(),
})

// Genuine service failure only — the app shows "AI service unavailable".
const degradedResponse = {
  subject_type: 'empty' as const,
  suggested_zoom: 1,
  degraded: true,
}

// When the model can't give usable guidance (says empty / returns an
// incomplete or malformed shape) we still hand the user something to align
// to: a generous, slightly-centered scene target. A camera pointed at
// anything has a scene — guidance must never dead-end.
const defaultSceneGuidance = {
  subject_type: 'scene' as const,
  target_x: 0.5,
  target_y: 0.48,
  target_w: 0.62,
  target_h: 0.72,
  suggested_zoom: 1,
}

export async function POST(req: Request) {
  const cfg = llmConfig()
  if (!cfg) return NextResponse.json({ error: 'misconfigured' }, { status: 500 })

  const parse = RequestBody.safeParse(await req.json().catch(() => ({})))
  if (!parse.success) return NextResponse.json({ error: 'bad_body' }, { status: 400 })

  // Debug output is gated behind a server env flag — the client header alone
  // must NOT expose raw LLM output to arbitrary callers.
  const debug = process.env.DEBUG_ENDPOINTS === '1' && req.headers.get('x-debug') === '1'

  try {
    const raw = await callVision(
      makeLLM(cfg.apiKey, cfg.baseURL),
      {
        system: COMPOSITION_SKILL,
        imageB64: parse.data.image_b64,
        mediaType: 'image/jpeg',
        maxTokens: 256,
      },
      cfg.model,
    )
    const ok = AIGuidanceSchema.safeParse(raw)
    if (!ok.success) {
      // Malformed model output — fall back to a usable scene target.
      return NextResponse.json(
        debug ? { ...defaultSceneGuidance, _debug: { reason: 'schema_reject', raw, issues: ok.error.issues } } : defaultSceneGuidance
      )
    }
    const g = ok.data
    // Schema marks pose_*/target_* optional, so a `person`/`scene` response can
    // pass Zod while missing fields the iOS overlay needs. Also the model may
    // return `empty`. In every such case the user still gets a usable target:
    // guidance never dead-ends.
    const incompletePerson = g.subject_type === 'person' &&
      (g.pose_id == null || g.pose_x == null || g.pose_y == null || g.pose_height == null)
    const incompleteScene = g.subject_type === 'scene' &&
      (g.target_x == null || g.target_y == null || g.target_w == null || g.target_h == null)
    if (g.subject_type === 'empty' || incompletePerson || incompleteScene) {
      const reason = g.subject_type === 'empty' ? 'model_empty' : 'incomplete_shape'
      return NextResponse.json(
        debug ? { ...defaultSceneGuidance, _debug: { reason, raw } } : defaultSceneGuidance
      )
    }
    return NextResponse.json(
      debug ? { ...g, _debug: { reason: 'ok', raw } } : g
    )
  } catch (e) {
    console.error('guidance', e)
    // Genuine service failure — flag degraded so the app shows "AI service
    // unavailable" rather than a misleading default target.
    return NextResponse.json(
      debug ? { ...degradedResponse, _debug: { reason: 'exception', error: String(e) } } : degradedResponse
    )
  }
}

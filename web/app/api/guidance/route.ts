// On-demand AI composition guidance. One call per "AI 指导" button tap on iOS.
// No rate limiting in v1; add Upstash if abuse appears.
import { NextResponse } from 'next/server'
import { z } from 'zod'
import { AIGuidanceSchema } from '@/lib/schemas'
import { GUIDANCE_SYSTEM_PROMPT_V4 } from '@/lib/prompts'
import { callVision, makeLLM, llmConfig } from '@/lib/llm'

export const runtime = 'nodejs'
export const maxDuration = 60
export const preferredRegion = ['hkg1']

const RequestBody = z.object({
  image_b64: z.string().min(1).max(2_000_000),
  client_version: z.string().optional(),
})

const emptyResponse = {
  subject_type: 'empty' as const,
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
        system: GUIDANCE_SYSTEM_PROMPT_V4,
        imageB64: parse.data.image_b64,
        mediaType: 'image/jpeg',
        maxTokens: 256,
      },
      cfg.model,
    )
    const ok = AIGuidanceSchema.safeParse(raw)
    if (!ok.success) {
      return NextResponse.json(
        debug ? { ...emptyResponse, _debug: { reason: 'schema_reject', raw, issues: ok.error.issues } } : emptyResponse
      )
    }
    // Schema marks pose_*/target_* optional, so a `person`/`scene` response can
    // pass Zod while missing the fields the iOS overlay needs. Treat such an
    // incomplete (but not service-failed) response as a plain empty result.
    const g = ok.data
    const incomplete =
      (g.subject_type === 'person' &&
        (g.pose_id == null || g.pose_x == null || g.pose_y == null || g.pose_height == null)) ||
      (g.subject_type === 'scene' &&
        (g.target_x == null || g.target_y == null || g.target_w == null || g.target_h == null))
    if (incomplete) {
      return NextResponse.json(
        debug ? { ...emptyResponse, _debug: { reason: 'incomplete_shape', raw } } : emptyResponse
      )
    }
    return NextResponse.json(
      debug ? { ...g, _debug: { reason: 'ok', raw } } : g
    )
  } catch (e) {
    console.error('guidance', e)
    // Genuine service failure — flag degraded so the app can tell this apart
    // from a real "no subject" empty result.
    const failed = { ...emptyResponse, degraded: true }
    return NextResponse.json(
      debug ? { ...failed, _debug: { reason: 'exception', error: String(e) } } : failed
    )
  }
}

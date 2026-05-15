// TODO: add Upstash Redis rate limiting (skill: zero-cost-deploy → Upstash)
import { NextResponse } from 'next/server'
import { z } from 'zod'
import { SceneAnalysisSchema, neutralGrade } from '@/lib/schemas'
import { COLORIST_SKILL } from '@/lib/colorist-skill'
import { callVision, makeLLM, llmConfig } from '@/lib/llm'

export const runtime = 'nodejs'
export const maxDuration = 60               // Hobby tier max — uyilink vision can take 15-40s cross-region
export const preferredRegion = ['hkg1']     // Hong Kong: closest Vercel region to sz.uyilink.com

const RequestBody = z.object({
  image_b64: z.string().min(1).max(2_000_000),
  client_version: z.string().optional(),
})

export async function POST(req: Request) {
  const cfg = llmConfig()
  if (!cfg) return NextResponse.json({ error: 'misconfigured' }, { status: 500 })

  const parse = RequestBody.safeParse(await req.json().catch(() => ({})))
  if (!parse.success) return NextResponse.json({ error: 'bad_body' }, { status: 400 })

  // Debug output is gated behind a server env flag — the client header alone
  // must NOT expose raw LLM output to arbitrary callers.
  const debugEnabled = process.env.DEBUG_ENDPOINTS === '1' && req.headers.get('x-debug') === '1'

  const neutralFallback = {
    scene: 'other' as const,
    lighting: 'mixed' as const,
    rationale: 'fallback: neutral preset',
    grade: neutralGrade(),
  }

  try {
    const raw = await callVision(
      makeLLM(cfg.apiKey, cfg.baseURL),
      {
        system: COLORIST_SKILL,
        imageB64: parse.data.image_b64,
        mediaType: 'image/jpeg',
        maxTokens: 1536,
        // >0 so the editor's "Retry" yields a fresh take instead of an identical grade.
        temperature: 0.7,
      },
      cfg.model,
    )
    const ok = SceneAnalysisSchema.safeParse(raw)
    if (!ok.success) return NextResponse.json({ ...neutralFallback, degraded: true })
    return NextResponse.json(ok.data)
  } catch (e) {
    console.error('grade', e)
    const debug = debugEnabled
        ? { _debug: e instanceof Error ? `${e.name}: ${e.message}` : String(e) }
        : {}
    return NextResponse.json({ ...neutralFallback, degraded: true, ...debug })
  }
}

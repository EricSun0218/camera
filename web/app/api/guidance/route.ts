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
    if (!ok.success) return NextResponse.json(emptyResponse)
    return NextResponse.json(ok.data)
  } catch (e) {
    console.error('guidance', e)
    return NextResponse.json(emptyResponse)
  }
}

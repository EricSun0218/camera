// TODO: add Upstash Redis rate limiting (skill: zero-cost-deploy → Upstash)
import { NextResponse } from 'next/server'
import { z } from 'zod'
import { CoachTipSchema } from '@/lib/schemas'
import { COACH_SYSTEM_PROMPT_V3 } from '@/lib/prompts'
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

  try {
    const raw = await callVision(
      makeLLM(cfg.apiKey, cfg.baseURL),
      {
        system: COACH_SYSTEM_PROMPT_V3,
        imageB64: parse.data.image_b64,
        mediaType: 'image/jpeg',
        maxTokens: 256,
      },
      cfg.model,
    )
    const tip = CoachTipSchema.safeParse(raw)
    if (!tip.success) return NextResponse.json({ tip: null, priority: 'low' })
    return NextResponse.json(tip.data)
  } catch (e) {
    console.error('coach', e)
    return NextResponse.json({ tip: null, priority: 'low' })
  }
}

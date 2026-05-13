// TODO: add Upstash Redis rate limiting (skill: zero-cost-deploy → Upstash)
import { NextResponse } from 'next/server'
import { z } from 'zod'
import { SceneAnalysisSchema, neutralGrade } from '@/lib/schemas'
import { COLORIST_SYSTEM_PROMPT_V1 } from '@/lib/prompts'
import { callClaudeVision, makeAnthropic } from '@/lib/anthropic'

export const runtime = 'nodejs'
export const maxDuration = 30

const RequestBody = z.object({
  image_b64: z.string().min(1).max(2_000_000),
  client_version: z.string().optional(),
})

export async function POST(req: Request) {
  const apiKey = process.env.ANTHROPIC_API_KEY
  const baseURL = process.env.ANTHROPIC_BASE_URL
  if (!apiKey) return NextResponse.json({ error: 'misconfigured' }, { status: 500 })

  const parse = RequestBody.safeParse(await req.json().catch(() => ({})))
  if (!parse.success) return NextResponse.json({ error: 'bad_body' }, { status: 400 })

  const neutralFallback = {
    scene: 'other' as const,
    lighting: 'mixed' as const,
    rationale: 'fallback: neutral preset',
    grade: neutralGrade(),
  }

  try {
    const raw = await callClaudeVision(makeAnthropic(apiKey, baseURL), {
      system: COLORIST_SYSTEM_PROMPT_V1,
      imageB64: parse.data.image_b64,
      mediaType: 'image/jpeg',
      maxTokens: 1536,
    })
    const ok = SceneAnalysisSchema.safeParse(raw)
    if (!ok.success) return NextResponse.json(neutralFallback)
    return NextResponse.json(ok.data)
  } catch (e) {
    console.error('grade', e)
    return NextResponse.json(neutralFallback)
  }
}

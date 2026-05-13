// TODO: add Upstash Redis rate limiting (skill: zero-cost-deploy → Upstash)
import { NextResponse } from 'next/server'
import { z } from 'zod'
import { CoachTipSchema } from '@/lib/schemas'
import { COACH_SYSTEM_PROMPT_V1 } from '@/lib/prompts'
import { callClaudeVision, makeAnthropic } from '@/lib/anthropic'

export const runtime = 'nodejs'
export const maxDuration = 30

const RequestBody = z.object({
  image_b64: z.string().min(1).max(2_000_000),
  client_version: z.string().optional(),
})

export async function POST(req: Request) {
  const apiKey = process.env.ANTHROPIC_API_KEY
  if (!apiKey) return NextResponse.json({ error: 'misconfigured' }, { status: 500 })

  const parse = RequestBody.safeParse(await req.json().catch(() => ({})))
  if (!parse.success) return NextResponse.json({ error: 'bad_body' }, { status: 400 })

  try {
    const raw = await callClaudeVision(makeAnthropic(apiKey), {
      system: COACH_SYSTEM_PROMPT_V1,
      imageB64: parse.data.image_b64,
      mediaType: 'image/jpeg',
      maxTokens: 256,
    })
    const tip = CoachTipSchema.safeParse(raw)
    if (!tip.success) return NextResponse.json({ tip: null, priority: 'low' })
    return NextResponse.json(tip.data)
  } catch (e) {
    console.error('coach', e)
    return NextResponse.json({ tip: null, priority: 'low' })
  }
}

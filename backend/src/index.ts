import { Hono } from 'hono'
import { z } from 'zod'
import { CoachTipSchema, SceneAnalysisSchema, neutralGrade } from './schemas'
import { COACH_SYSTEM_PROMPT_V1, COLORIST_SYSTEM_PROMPT_V1 } from './prompts'
import * as anthropicModule from './anthropic'
import { makeAnthropic } from './anthropic'
import { take } from './ratelimit'

type Bindings = {
  ANTHROPIC_API_KEY: string
  RATELIMIT: KVNamespace
}

const RequestBody = z.object({
  image_b64: z.string().min(1).max(2_000_000),
  client_version: z.string().optional(),
})

const COACH_LIMIT = 30
const GRADE_LIMIT = 10
const WINDOW_MS = 3600_000

const app = new Hono<{ Bindings: Bindings }>()

app.get('/', (c) => c.text('Auteur backend'))

app.post('/coach', async (c) => {
  const ip = c.req.header('cf-connecting-ip') ?? 'anon'
  const limit = await take(c.env.RATELIMIT, ip, 'coach', COACH_LIMIT, WINDOW_MS)
  if (!limit.ok) {
    return c.json({ error: 'rate_limited' }, 429, { 'Retry-After': String(limit.retryAfterSec) })
  }

  const parse = RequestBody.safeParse(await c.req.json().catch(() => ({})))
  if (!parse.success) return c.json({ error: 'bad_body' }, 400)

  try {
    const raw = await anthropicModule.callClaudeVision(makeAnthropic(c.env.ANTHROPIC_API_KEY), {
      system: COACH_SYSTEM_PROMPT_V1,
      imageB64: parse.data.image_b64,
      mediaType: 'image/jpeg',
      maxTokens: 256,
    })
    const tip = CoachTipSchema.safeParse(raw)
    if (!tip.success) return c.json({ tip: null, priority: 'low' })
    return c.json(tip.data)
  } catch (e) {
    console.error('coach', e)
    return c.json({ tip: null, priority: 'low' })
  }
})

app.post('/grade', async (c) => {
  const ip = c.req.header('cf-connecting-ip') ?? 'anon'
  const limit = await take(c.env.RATELIMIT, ip, 'grade', GRADE_LIMIT, WINDOW_MS)
  if (!limit.ok) {
    return c.json({ error: 'rate_limited' }, 429, { 'Retry-After': String(limit.retryAfterSec) })
  }

  const parse = RequestBody.safeParse(await c.req.json().catch(() => ({})))
  if (!parse.success) return c.json({ error: 'bad_body' }, 400)

  const neutralFallback = {
    scene: 'other' as const, lighting: 'mixed' as const,
    rationale: 'fallback: neutral preset', grade: neutralGrade(),
  }

  try {
    const raw = await anthropicModule.callClaudeVision(makeAnthropic(c.env.ANTHROPIC_API_KEY), {
      system: COLORIST_SYSTEM_PROMPT_V1,
      imageB64: parse.data.image_b64,
      mediaType: 'image/jpeg',
      maxTokens: 1536,
    })
    const ok = SceneAnalysisSchema.safeParse(raw)
    if (!ok.success) return c.json(neutralFallback)
    return c.json(ok.data)
  } catch (e) {
    console.error('grade', e)
    return c.json(neutralFallback)
  }
})

export default app

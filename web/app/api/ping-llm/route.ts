// Diagnostic-only endpoint. Hits the LLM with a tiny text-only call so we can
// distinguish "uyilink unreachable from this Vercel region" from "vision call
// is slow but works".
import { NextResponse } from 'next/server'
import { llmConfig, makeLLM } from '@/lib/llm'

export const runtime = 'nodejs'
export const maxDuration = 60
export const preferredRegion = ['hkg1']

export async function GET() {
  const cfg = llmConfig()
  if (!cfg) return NextResponse.json({ error: 'misconfigured' }, { status: 500 })

  const t0 = Date.now()
  try {
    const c = makeLLM(cfg.apiKey, cfg.baseURL)
    const resp = await c.chat.completions.create({
      model: cfg.model,
      max_tokens: 10,
      temperature: 0,
      messages: [{ role: 'user', content: 'reply with just OK' }],
    })
    return NextResponse.json({
      ok: true,
      elapsed_ms: Date.now() - t0,
      model: resp.model,
      text: resp.choices?.[0]?.message?.content,
      region: process.env.VERCEL_REGION,
    })
  } catch (e) {
    return NextResponse.json({
      ok: false,
      elapsed_ms: Date.now() - t0,
      error: e instanceof Error ? `${e.name}: ${e.message}` : String(e),
      region: process.env.VERCEL_REGION,
    }, { status: 200 })
  }
}

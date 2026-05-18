/**
 * LLM client — OpenAI-compatible HTTP API.
 *
 * Despite the project shipping Claude-tuned system prompts, we hit the model
 * through an OpenAI Chat Completions-shaped endpoint (e.g. the uyilink reseller
 * proxy). The proxy translates internally to whatever upstream provider it uses.
 *
 * Why OpenAI SDK (not Anthropic SDK):
 *   - Most commodity LLM gateways expose the OpenAI protocol.
 *   - Vision needs `image_url` (data URL) message parts, not Anthropic's
 *     `image` source block.
 *
 * Env contract (set in Vercel, never hardcoded):
 *   LLM_API_KEY   — bearer token for the proxy
 *   LLM_BASE_URL  — fully-qualified base URL ending in /v1 (e.g. https://sz.uyilink.com/v1)
 *   LLM_MODEL     — model name accepted by the proxy (default: claude-sonnet-4-6)
 */
import OpenAI from 'openai'

export const DEFAULT_MODEL = 'claude-sonnet-4-6'

type CallArgs = {
  system: string
  imageB64: string
  mediaType: 'image/jpeg' | 'image/png'
  maxTokens?: number
  /** 0 = deterministic. The grade route uses >0 so "retry" yields a fresh take. */
  temperature?: number
}

export async function callVision(
  client: Pick<OpenAI, 'chat'>,
  args: CallArgs,
  model: string,
): Promise<unknown> {
  const dataUrl = `data:${args.mediaType};base64,${args.imageB64}`
  const resp = await client.chat.completions.create({
    model,
    max_tokens: args.maxTokens ?? 1024,
    temperature: args.temperature ?? 0,
    messages: [
      { role: 'system', content: args.system },
      {
        role: 'user',
        content: [
          { type: 'text',      text: 'Return JSON only.' },
          { type: 'image_url', image_url: { url: dataUrl } },
        ],
      },
    ],
  })
  const text = resp.choices?.[0]?.message?.content
  if (typeof text !== 'string' || text.length === 0) {
    throw new Error('LLM returned non-text content')
  }
  return parseJsonLoose(text)
}

function parseJsonLoose(text: string): unknown {
  const trimmed = text.trim()

  // 1) First fenced ```json ... ``` block, even with prose before/after.
  //    Non-anchored: an LLM reply that wraps the fence in commentary still parses.
  const fenced = /```(?:json)?\s*([\s\S]*?)```/i.exec(trimmed)
  if (fenced) {
    const body = fenced[1].trim()
    try {
      return JSON.parse(body)
    } catch {
      // fall through to balanced-object scan below
    }
  }

  // 2) No (parseable) fence — extract the first balanced top-level {...} object.
  const obj = extractBalancedObject(trimmed)
  if (obj !== null) {
    try {
      return JSON.parse(obj)
    } catch {
      // fall through to throw
    }
  }

  // 3) Last resort — maybe the whole thing is bare JSON.
  try {
    return JSON.parse(trimmed)
  } catch {
    throw new Error(`LLM response was not JSON: ${trimmed.slice(0, 200)}`)
  }
}

/** Returns the first balanced `{...}` substring via a brace-matching scan, or null. */
function extractBalancedObject(text: string): string | null {
  const start = text.indexOf('{')
  if (start === -1) return null
  let depth = 0
  let inStr = false
  let escaped = false
  for (let i = start; i < text.length; i++) {
    const ch = text[i]
    if (inStr) {
      if (escaped) escaped = false
      else if (ch === '\\') escaped = true
      else if (ch === '"') inStr = false
      continue
    }
    if (ch === '"') inStr = true
    else if (ch === '{') depth++
    else if (ch === '}') {
      depth--
      if (depth === 0) return text.slice(start, i + 1)
    }
  }
  return null
}

export function makeLLM(apiKey: string, baseURL: string): OpenAI {
  // 45s timeout — vision via cross-border proxies routinely take 10–40s.
  // maxRetries: 0 is load-bearing — the SDK retries twice by default, and a
  // timed-out attempt would retry into 45s + 45s + 45s, far past the route's
  // 60s `maxDuration`. With no retries the single attempt aborts at 45s and
  // the route's catch/fallback returns before Vercel kills the function (504).
  return new OpenAI({ apiKey, baseURL, timeout: 45_000, maxRetries: 0 })
}

/** Read env config in one place so routes don't have to. */
export function llmConfig(): { apiKey: string; baseURL: string; model: string } | null {
  const apiKey  = process.env.LLM_API_KEY
  const baseURL = process.env.LLM_BASE_URL
  const model   = process.env.LLM_MODEL || DEFAULT_MODEL
  if (!apiKey || !baseURL) return null
  return { apiKey, baseURL, model }
}

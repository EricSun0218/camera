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
    temperature: 0,
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
  // strip ```json ... ``` if present
  const fenced = /^```(?:json)?\s*([\s\S]*?)\s*```$/i.exec(trimmed)
  const body = fenced ? fenced[1] : trimmed
  try {
    return JSON.parse(body)
  } catch {
    throw new Error(`LLM response was not JSON: ${body.slice(0, 200)}`)
  }
}

export function makeLLM(apiKey: string, baseURL: string): OpenAI {
  // 60s timeout — vision via cross-border reseller proxies routinely take 10–40s.
  return new OpenAI({ apiKey, baseURL, timeout: 60_000 })
}

/** Read env config in one place so routes don't have to. */
export function llmConfig(): { apiKey: string; baseURL: string; model: string } | null {
  const apiKey  = process.env.LLM_API_KEY
  const baseURL = process.env.LLM_BASE_URL
  const model   = process.env.LLM_MODEL || DEFAULT_MODEL
  if (!apiKey || !baseURL) return null
  return { apiKey, baseURL, model }
}

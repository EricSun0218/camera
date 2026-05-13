import Anthropic from '@anthropic-ai/sdk'

export const CLAUDE_MODEL = 'claude-sonnet-4-6'

type CallArgs = {
  system: string
  imageB64: string
  mediaType: 'image/jpeg' | 'image/png'
  maxTokens?: number
}

export async function callClaudeVision(
  client: Pick<Anthropic, 'messages'>,
  args: CallArgs,
): Promise<unknown> {
  const resp = await client.messages.create({
    model: CLAUDE_MODEL,
    max_tokens: args.maxTokens ?? 1024,
    system: args.system,
    messages: [
      {
        role: 'user',
        content: [
          { type: 'image', source: { type: 'base64', media_type: args.mediaType, data: args.imageB64 } },
          { type: 'text', text: 'Return JSON only.' },
        ],
      },
    ],
  })
  const first = resp.content[0]
  if (!first || first.type !== 'text') {
    throw new Error('Claude returned non-text content')
  }
  return parseJsonLoose(first.text)
}

function parseJsonLoose(text: string): unknown {
  const trimmed = text.trim()
  // strip ```json ... ``` if present
  const fenced = /^```(?:json)?\s*([\s\S]*?)\s*```$/i.exec(trimmed)
  const body = fenced ? fenced[1] : trimmed
  try {
    return JSON.parse(body)
  } catch (e) {
    throw new Error(`Claude response was not JSON: ${body.slice(0, 200)}`)
  }
}

export function makeAnthropic(apiKey: string, baseURL?: string): Anthropic {
  return new Anthropic(baseURL ? { apiKey, baseURL } : { apiKey })
}

import { describe, it, expect, vi } from 'vitest'
import { callVision } from '../lib/llm'

function fakeOpenAI(text: string) {
  return {
    chat: {
      completions: {
        create: vi.fn().mockResolvedValue({
          choices: [{ message: { content: text } }],
        }),
      },
    },
  }
}

describe('callVision', () => {
  it('strips ```json fences from response', async () => {
    const client = fakeOpenAI('```json\n{"a":1}\n```')
    const out = await callVision(client as any, {
      system: 'sys', imageB64: 'xxx', mediaType: 'image/jpeg',
    }, 'test-model')
    expect(out).toEqual({ a: 1 })
  })

  it('parses raw json', async () => {
    const client = fakeOpenAI('{"b":2}')
    const out = await callVision(client as any, {
      system: 'sys', imageB64: 'xxx', mediaType: 'image/jpeg',
    }, 'test-model')
    expect(out).toEqual({ b: 2 })
  })

  it('throws on non-json text', async () => {
    const client = fakeOpenAI('I cannot help.')
    await expect(callVision(client as any, {
      system: 'sys', imageB64: 'xxx', mediaType: 'image/jpeg',
    }, 'test-model')).rejects.toThrow(/JSON/)
  })

  it('throws on empty response', async () => {
    const client = fakeOpenAI('')
    await expect(callVision(client as any, {
      system: 'sys', imageB64: 'xxx', mediaType: 'image/jpeg',
    }, 'test-model')).rejects.toThrow(/non-text/)
  })
})

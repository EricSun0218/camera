import { describe, it, expect, vi } from 'vitest'
import { callClaudeVision } from '../src/anthropic'

describe('callClaudeVision', () => {
  it('strips ```json fences from response', async () => {
    const fakeSDK = {
      messages: {
        create: vi.fn().mockResolvedValue({
          content: [{ type: 'text', text: '```json\n{"a":1}\n```' }],
        }),
      },
    }
    const out = await callClaudeVision(fakeSDK as any, {
      system: 'sys', imageB64: 'xxx', mediaType: 'image/jpeg',
    })
    expect(out).toEqual({ a: 1 })
  })

  it('parses raw json', async () => {
    const fakeSDK = {
      messages: { create: vi.fn().mockResolvedValue({
        content: [{ type: 'text', text: '{"b":2}' }],
      }) },
    }
    const out = await callClaudeVision(fakeSDK as any, {
      system: 'sys', imageB64: 'xxx', mediaType: 'image/jpeg',
    })
    expect(out).toEqual({ b: 2 })
  })

  it('throws on non-json text', async () => {
    const fakeSDK = {
      messages: { create: vi.fn().mockResolvedValue({
        content: [{ type: 'text', text: 'I cannot help.' }],
      }) },
    }
    await expect(callClaudeVision(fakeSDK as any, {
      system: 'sys', imageB64: 'xxx', mediaType: 'image/jpeg',
    })).rejects.toThrow(/JSON/)
  })
})

# Cue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Cue iOS app and its Cloudflare Worker backend per `docs/superpowers/specs/2026-05-13-cue-design.md`. Deliverable is "ready to open in Xcode and deploy to Cloudflare" — no Xcode is available in this environment, so iOS verification is deferred to the user.

**Architecture:** SwiftUI iOS app (camera + on-device CV + Core Image grading), TypeScript Hono Worker proxying Anthropic Claude vision. Two LLM endpoints: `/coach` (live composition tip, ~2s cadence) and `/grade` (scene analysis + GradeParams JSON, once per shutter). All pixel ops in Core Image; LLM emits structured JSON only.

**Tech Stack:** Swift 5.10, SwiftUI, AVFoundation, Vision, CoreMotion, Core Image, xcodegen / TypeScript, Hono, Zod, Cloudflare Workers, miniflare, Vitest / Anthropic SDK (`@anthropic-ai/sdk`), model `claude-sonnet-4-6`.

**Verification policy:**
- Worker tasks (TypeScript) — fully verifiable now (`npm test` via vitest+miniflare).
- iOS tasks (Swift) — cannot be compiled in this environment (only Apple Command Line Tools, no Xcode/iOS SDK). Each Swift task ends in "Commit". The user verifies by opening `app/Cue.xcodeproj` in Xcode after install.

---

## Phase 0 — Project bootstrap

### Task 0.1: Top-level README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README**

```markdown
# Cue

iOS camera app: AI scene-adaptive auto color grading + real-time composition guidance.

LLM analyzes; deterministic Core Image renders.

## Setup

### Requirements
- macOS 14+ with Xcode 16+ installed (App Store)
- An Anthropic API key
- A Cloudflare account + `wrangler` CLI (`npm i -g wrangler`)

### iOS app
1. `cd app && xcodegen generate`
2. Open `Cue.xcodeproj` in Xcode
3. Set your development team in target signing
4. Edit `Cue/LLM/BackendClient.swift` — set `backendBaseURL` to your deployed Worker
5. Build + run on an iPhone (camera does not work in simulator)

### Backend (Cloudflare Worker)
1. `cd backend && npm install`
2. `npx wrangler secret put ANTHROPIC_API_KEY`
3. `npx wrangler kv namespace create RATELIMIT` — paste returned `id` into `wrangler.toml`
4. `npx wrangler deploy`
5. Note the deployed URL; paste it into `BackendClient.swift`

### Tests
- Backend: `cd backend && npm test`
- iOS: open in Xcode, ⌘U

## Architecture
See `docs/superpowers/specs/2026-05-13-cue-design.md`.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: top-level README"
```

---

### Task 0.2: `.gitignore`

**Files:**
- Create: `.gitignore`

- [ ] **Step 1: Write gitignore**

```gitignore
# macOS
.DS_Store

# Xcode
*.xcodeproj/xcuserdata/
*.xcworkspace/xcuserdata/
DerivedData/
build/
*.xcuserstate

# Swift Package Manager
.build/
Packages/
Package.resolved

# Node / Wrangler
node_modules/
.wrangler/
.dev.vars
dist/

# Generated
*.xcodeproj
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: gitignore"
```

---

## Phase 1 — Backend Worker (Hono + Anthropic, full TDD)

### Task 1.1: Bootstrap Worker package

**Files:**
- Create: `backend/package.json`
- Create: `backend/tsconfig.json`
- Create: `backend/wrangler.toml`
- Create: `backend/src/index.ts` (stub)
- Create: `backend/vitest.config.ts`

- [ ] **Step 1: `package.json`**

```json
{
  "name": "cue-backend",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "wrangler dev",
    "deploy": "wrangler deploy",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "dependencies": {
    "@anthropic-ai/sdk": "^0.32.1",
    "hono": "^4.6.0",
    "zod": "^3.23.0"
  },
  "devDependencies": {
    "@cloudflare/vitest-pool-workers": "^0.5.0",
    "@cloudflare/workers-types": "^4.20250101.0",
    "typescript": "^5.6.0",
    "vitest": "1.5.0",
    "wrangler": "^3.90.0"
  }
}
```

- [ ] **Step 2: `tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ES2022",
    "moduleResolution": "Bundler",
    "lib": ["ES2022"],
    "types": ["@cloudflare/workers-types"],
    "strict": true,
    "noImplicitAny": true,
    "esModuleInterop": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "skipLibCheck": true,
    "noEmit": true
  },
  "include": ["src/**/*", "test/**/*"]
}
```

- [ ] **Step 3: `wrangler.toml`**

```toml
name = "cue-backend"
main = "src/index.ts"
compatibility_date = "2025-01-01"

[[kv_namespaces]]
binding = "RATELIMIT"
id = "PASTE_KV_ID_HERE"   # `wrangler kv namespace create RATELIMIT`

[vars]
LOG_LEVEL = "info"
```

- [ ] **Step 4: `src/index.ts` stub**

```typescript
import { Hono } from 'hono'

type Bindings = {
  ANTHROPIC_API_KEY: string
  RATELIMIT: KVNamespace
}

const app = new Hono<{ Bindings: Bindings }>()

app.get('/', (c) => c.text('Cue backend'))

export default app
```

- [ ] **Step 5: `vitest.config.ts`**

```typescript
import { defineWorkersConfig } from '@cloudflare/vitest-pool-workers/config'

export default defineWorkersConfig({
  test: {
    poolOptions: {
      workers: {
        wrangler: { configPath: './wrangler.toml' },
      },
    },
  },
})
```

- [ ] **Step 6: Install + smoke**

```bash
cd backend && npm install
```

Expected: install succeeds, no peer-dependency errors.

- [ ] **Step 7: Commit**

```bash
git add backend/
git commit -m "feat(backend): bootstrap Hono worker"
```

---

### Task 1.2: Zod schemas

**Files:**
- Create: `backend/src/schemas.ts`
- Create: `backend/test/schemas.test.ts`

- [ ] **Step 1: Write the failing test**

```typescript
// backend/test/schemas.test.ts
import { describe, it, expect } from 'vitest'
import { GradeParamsSchema, SceneAnalysisSchema, CoachTipSchema, neutralGrade } from '../src/schemas'

describe('CoachTipSchema', () => {
  it('accepts a tip with length <= 80', () => {
    expect(CoachTipSchema.parse({ tip: 'step left', priority: 'med' })).toEqual({
      tip: 'step left', priority: 'med',
    })
  })

  it('accepts null tip', () => {
    expect(CoachTipSchema.parse({ tip: null, priority: 'low' })).toEqual({
      tip: null, priority: 'low',
    })
  })

  it('rejects tip > 80 chars', () => {
    expect(() => CoachTipSchema.parse({ tip: 'x'.repeat(81), priority: 'med' })).toThrow()
  })

  it('rejects invalid priority', () => {
    expect(() => CoachTipSchema.parse({ tip: 'x', priority: 'urgent' })).toThrow()
  })
})

describe('GradeParamsSchema', () => {
  it('accepts neutral grade', () => {
    expect(() => GradeParamsSchema.parse(neutralGrade())).not.toThrow()
  })

  it('clamps exposure_ev to [-2,2]', () => {
    expect(() => GradeParamsSchema.parse({ ...neutralGrade(), exposure_ev: 3 })).toThrow()
  })

  it('requires all 8 hsl bands', () => {
    const g = neutralGrade()
    delete (g.hsl as any).red
    expect(() => GradeParamsSchema.parse(g)).toThrow()
  })

  it('clamps hsl hue to [-30,30]', () => {
    const g = neutralGrade()
    g.hsl.red.hue = 31
    expect(() => GradeParamsSchema.parse(g)).toThrow()
  })
})

describe('SceneAnalysisSchema', () => {
  it('rejects unknown scene', () => {
    expect(() => SceneAnalysisSchema.parse({
      scene: 'underwater', lighting: 'harsh_sun', rationale: 'x', grade: neutralGrade(),
    })).toThrow()
  })

  it('rejects rationale > 120', () => {
    expect(() => SceneAnalysisSchema.parse({
      scene: 'portrait', lighting: 'harsh_sun', rationale: 'x'.repeat(121), grade: neutralGrade(),
    })).toThrow()
  })

  it('accepts a complete valid payload', () => {
    const ok = SceneAnalysisSchema.parse({
      scene: 'portrait', lighting: 'golden_hour', rationale: 'warm soft skin', grade: neutralGrade(),
    })
    expect(ok.scene).toBe('portrait')
  })
})
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd backend && npm test -- --reporter=verbose
```

Expected: tests fail because `../src/schemas` doesn't exist.

- [ ] **Step 3: Implement `schemas.ts`**

```typescript
// backend/src/schemas.ts
import { z } from 'zod'

const HSL_BANDS = ['red','orange','yellow','green','aqua','blue','purple','magenta'] as const

const HslBandSchema = z.object({
  hue:        z.number().min(-30).max(30),
  saturation: z.number().min(-100).max(100),
  luminance:  z.number().min(-100).max(100),
})

export const GradeParamsSchema = z.object({
  exposure_ev: z.number().min(-2).max(2),
  contrast:    z.number().min(-50).max(50),
  highlights:  z.number().min(-100).max(100),
  shadows:     z.number().min(-100).max(100),
  whites:      z.number().min(-100).max(100),
  blacks:      z.number().min(-100).max(100),
  saturation:  z.number().min(-100).max(100),
  vibrance:    z.number().min(-100).max(100),
  temperature: z.number().min(-100).max(100),
  tint:        z.number().min(-100).max(100),
  hsl: z.object(Object.fromEntries(HSL_BANDS.map(b => [b, HslBandSchema])) as Record<typeof HSL_BANDS[number], typeof HslBandSchema>),
  vignette_intensity: z.number().min(0).max(1),
  vignette_radius:    z.number().min(0.5).max(2),
})

export type GradeParams = z.infer<typeof GradeParamsSchema>

export const SceneSchema = z.enum([
  'portrait','group','food','landscape','urban','night','interior','product','pet','document','other',
])
export const LightingSchema = z.enum([
  'harsh_sun','golden_hour','overcast','shade','indoor_warm','indoor_cool','mixed','low_light','flash',
])

export const SceneAnalysisSchema = z.object({
  scene:     SceneSchema,
  lighting:  LightingSchema,
  rationale: z.string().max(120),
  grade:     GradeParamsSchema,
})

export type SceneAnalysis = z.infer<typeof SceneAnalysisSchema>

export const CoachTipSchema = z.object({
  tip:      z.string().max(80).nullable(),
  priority: z.enum(['low','med','high']),
})

export type CoachTip = z.infer<typeof CoachTipSchema>

export function neutralGrade(): GradeParams {
  const flatBand = { hue: 0, saturation: 0, luminance: 0 }
  return {
    exposure_ev: 0, contrast: 0,
    highlights: 0, shadows: 0, whites: 0, blacks: 0,
    saturation: 0, vibrance: 0,
    temperature: 0, tint: 0,
    hsl: Object.fromEntries(HSL_BANDS.map(b => [b, { ...flatBand }])) as GradeParams['hsl'],
    vignette_intensity: 0, vignette_radius: 1,
  }
}
```

- [ ] **Step 4: Run — expect PASS**

```bash
cd backend && npm test
```

Expected: all schema tests pass.

- [ ] **Step 5: Commit**

```bash
git add backend/src/schemas.ts backend/test/schemas.test.ts
git commit -m "feat(backend): zod schemas for grade params, scene analysis, coach tip"
```

---

### Task 1.3: Versioned prompts

**Files:**
- Create: `backend/src/prompts.ts`

- [ ] **Step 1: Write prompts**

```typescript
// backend/src/prompts.ts

export const COACH_SYSTEM_PROMPT_V1 = `You are a photographer's composition coach. You see a single live-viewfinder snapshot. Identify at most ONE issue that, if fixed, would meaningfully improve the photo. Prioritize:

1. Tilted horizon (advise rotation, e.g. "level — rotate ~3° clockwise").
2. Cluttered or distracting background.
3. Subject too small / too centered when off-center would be stronger.
4. Harsh lighting on subject — suggest moving relative to sun, or waiting.
5. Cut-off limbs or critical edges.

If the framing is already strong, return tip: null.

OUTPUT FORMAT: Strict JSON, no prose, conforming to:
{ "tip": "<one short imperative, <=80 chars>" | null, "priority": "low" | "med" | "high" }

Be concise. The tip is shown as a bottom banner; user reads in <1s.`

export const COLORIST_SYSTEM_PROMPT_V1 = `You are a senior colorist analyzing a single still photo. Your output:

1. Identify scene from: portrait, group, food, landscape, urban, night, interior, product, pet, document, other.
2. Identify lighting from: harsh_sun, golden_hour, overcast, shade, indoor_warm, indoor_cool, mixed, low_light, flash.
3. Write a one-sentence rationale, <=120 chars.
4. Prescribe a "grade" object — color adjustments suited to the genre.

Genre guidance:
- Portrait/Group → warm tone, soft skin (gentle shadow lift +10..+25), red/orange HSL saturation slight cut to avoid over-redness, never over-saturate.
- Food → vibrant (vibrance +20..+40), warm temperature (+5..+15), pull greens darker (green luminance -10..-20), slight contrast.
- Landscape → punchy skies (blue saturation +10..+25, blue luminance -5..-15), deeper greens, mild dehaze (whites +5..+15, blacks -10..-20), low vignette ok.
- Night → lift shadows (+15..+30) but keep blacks crushed (blacks -10..-25), reduce highlights (-20..-40), slight cool tint (temperature -5..-15) to fight sodium-vapor cast.
- Interior → correct WB first (small temperature/tint), vibrance not saturation, lift shadows.
- Document → flat, neutral, contrast 0, saturation -50 if dramatically color-shifted.
- Product/Pet/Urban/Other → conservative, scene-appropriate.

Default to subtle. Most numeric values should sit in ±30. Reserve big magnitudes for clear corrections.

OUTPUT FORMAT: Strict JSON. NO prose outside JSON. Conform to:
{
  "scene": "<enum>",
  "lighting": "<enum>",
  "rationale": "<=120 chars>",
  "grade": {
    "exposure_ev": <-2..2>,
    "contrast": <-50..50>,
    "highlights": <-100..100>, "shadows": <-100..100>,
    "whites": <-100..100>, "blacks": <-100..100>,
    "saturation": <-100..100>, "vibrance": <-100..100>,
    "temperature": <-100..100>, "tint": <-100..100>,
    "hsl": {
      "red":{"hue":<-30..30>,"saturation":<-100..100>,"luminance":<-100..100>},
      "orange":{...}, "yellow":{...}, "green":{...},
      "aqua":{...}, "blue":{...}, "purple":{...}, "magenta":{...}
    },
    "vignette_intensity": <0..1>, "vignette_radius": <0.5..2>
  }
}

All 8 HSL bands MUST be present even if zero.`
```

- [ ] **Step 2: Commit**

```bash
git add backend/src/prompts.ts
git commit -m "feat(backend): versioned coach + colorist system prompts"
```

---

### Task 1.4: Anthropic client

**Files:**
- Create: `backend/src/anthropic.ts`
- Create: `backend/test/anthropic.test.ts`

- [ ] **Step 1: Failing test**

```typescript
// backend/test/anthropic.test.ts
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
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd backend && npm test test/anthropic.test.ts
```

- [ ] **Step 3: Implement**

```typescript
// backend/src/anthropic.ts
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

export function makeAnthropic(apiKey: string): Anthropic {
  return new Anthropic({ apiKey })
}
```

- [ ] **Step 4: Run — expect PASS**

```bash
cd backend && npm test test/anthropic.test.ts
```

- [ ] **Step 5: Commit**

```bash
git add backend/src/anthropic.ts backend/test/anthropic.test.ts
git commit -m "feat(backend): anthropic vision wrapper with loose JSON parsing"
```

---

### Task 1.5: Rate limiter (KV token bucket)

**Files:**
- Create: `backend/src/ratelimit.ts`
- Create: `backend/test/ratelimit.test.ts`

- [ ] **Step 1: Failing test**

```typescript
// backend/test/ratelimit.test.ts
import { describe, it, expect } from 'vitest'
import { env } from 'cloudflare:test'
import { take } from '../src/ratelimit'

describe('rate limiter', () => {
  it('first call passes for given ip+route', async () => {
    const r = await take(env.RATELIMIT, '1.1.1.1', 'coach', 30, 3600_000)
    expect(r.ok).toBe(true)
    expect(r.remaining).toBe(29)
  })

  it('depletes after N calls', async () => {
    const ip = '2.2.2.2'
    for (let i = 0; i < 30; i++) await take(env.RATELIMIT, ip, 'coach', 30, 3600_000)
    const r = await take(env.RATELIMIT, ip, 'coach', 30, 3600_000)
    expect(r.ok).toBe(false)
    expect(r.retryAfterSec).toBeGreaterThan(0)
  })

  it('routes are independent', async () => {
    const ip = '3.3.3.3'
    for (let i = 0; i < 10; i++) await take(env.RATELIMIT, ip, 'grade', 10, 3600_000)
    const grade = await take(env.RATELIMIT, ip, 'grade', 10, 3600_000)
    const coach = await take(env.RATELIMIT, ip, 'coach', 30, 3600_000)
    expect(grade.ok).toBe(false)
    expect(coach.ok).toBe(true)
  })
})
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

```typescript
// backend/src/ratelimit.ts

export type Bucket = { remaining: number; resetAt: number }
export type TakeResult =
  | { ok: true; remaining: number }
  | { ok: false; retryAfterSec: number }

export async function take(
  kv: KVNamespace,
  ip: string,
  route: 'coach' | 'grade',
  capacity: number,
  windowMs: number,
): Promise<TakeResult> {
  const key = `rl:${route}:${ip}`
  const now = Date.now()
  const raw = await kv.get(key, 'json') as Bucket | null

  let bucket: Bucket
  if (!raw || raw.resetAt <= now) {
    bucket = { remaining: capacity, resetAt: now + windowMs }
  } else {
    bucket = raw
  }

  if (bucket.remaining <= 0) {
    return { ok: false, retryAfterSec: Math.max(1, Math.ceil((bucket.resetAt - now) / 1000)) }
  }

  bucket.remaining -= 1
  await kv.put(key, JSON.stringify(bucket), { expirationTtl: Math.ceil(windowMs / 1000) + 60 })
  return { ok: true, remaining: bucket.remaining }
}
```

- [ ] **Step 4: Run — expect PASS**

```bash
cd backend && npm test test/ratelimit.test.ts
```

- [ ] **Step 5: Commit**

```bash
git add backend/src/ratelimit.ts backend/test/ratelimit.test.ts
git commit -m "feat(backend): per-ip token-bucket rate limiter in KV"
```

---

### Task 1.6: Hono routes (/coach, /grade)

**Files:**
- Modify: `backend/src/index.ts`
- Create: `backend/test/routes.test.ts`

- [ ] **Step 1: Failing test**

```typescript
// backend/test/routes.test.ts
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { env, SELF } from 'cloudflare:test'
import * as anthropicModule from '../src/anthropic'

// fake call
const fakeCoach = { tip: 'step left', priority: 'med' as const }
const fakeGrade = {
  scene: 'portrait', lighting: 'golden_hour', rationale: 'warm',
  grade: {
    exposure_ev: 0.1, contrast: 5, highlights: -20, shadows: 15, whites: 0, blacks: -5,
    saturation: 0, vibrance: 10, temperature: 5, tint: 0,
    hsl: {
      red:{hue:0,saturation:-5,luminance:0}, orange:{hue:0,saturation:0,luminance:0},
      yellow:{hue:0,saturation:0,luminance:0}, green:{hue:0,saturation:0,luminance:0},
      aqua:{hue:0,saturation:0,luminance:0}, blue:{hue:0,saturation:0,luminance:0},
      purple:{hue:0,saturation:0,luminance:0}, magenta:{hue:0,saturation:0,luminance:0},
    },
    vignette_intensity: 0, vignette_radius: 1,
  },
}

beforeEach(() => {
  vi.restoreAllMocks()
})

describe('routes', () => {
  it('GET / returns hello', async () => {
    const r = await SELF.fetch('https://x/')
    expect(r.status).toBe(200)
  })

  it('POST /coach returns parsed tip', async () => {
    vi.spyOn(anthropicModule, 'callClaudeVision').mockResolvedValue(fakeCoach)
    const r = await SELF.fetch('https://x/coach', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'cf-connecting-ip': '9.9.9.1' },
      body: JSON.stringify({ image_b64: 'xx', client_version: '1.0.0' }),
    })
    expect(r.status).toBe(200)
    expect(await r.json()).toEqual(fakeCoach)
  })

  it('POST /grade returns parsed scene analysis', async () => {
    vi.spyOn(anthropicModule, 'callClaudeVision').mockResolvedValue(fakeGrade)
    const r = await SELF.fetch('https://x/grade', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'cf-connecting-ip': '9.9.9.2' },
      body: JSON.stringify({ image_b64: 'xx', client_version: '1.0.0' }),
    })
    expect(r.status).toBe(200)
    const body = await r.json() as any
    expect(body.scene).toBe('portrait')
  })

  it('POST /coach rate-limits after 30 calls', async () => {
    vi.spyOn(anthropicModule, 'callClaudeVision').mockResolvedValue(fakeCoach)
    const ip = '9.9.9.3'
    for (let i = 0; i < 30; i++) {
      await SELF.fetch('https://x/coach', {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'cf-connecting-ip': ip },
        body: JSON.stringify({ image_b64: 'xx' }),
      })
    }
    const r = await SELF.fetch('https://x/coach', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'cf-connecting-ip': ip },
      body: JSON.stringify({ image_b64: 'xx' }),
    })
    expect(r.status).toBe(429)
    expect(r.headers.get('retry-after')).not.toBeNull()
  })

  it('rejects bad body', async () => {
    const r = await SELF.fetch('https://x/coach', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'cf-connecting-ip': '9.9.9.4' },
      body: JSON.stringify({}),
    })
    expect(r.status).toBe(400)
  })

  it('falls back to neutral grade if Claude returns invalid JSON shape', async () => {
    vi.spyOn(anthropicModule, 'callClaudeVision').mockResolvedValue({ totally: 'wrong' })
    const r = await SELF.fetch('https://x/grade', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'cf-connecting-ip': '9.9.9.5' },
      body: JSON.stringify({ image_b64: 'xx' }),
    })
    expect(r.status).toBe(200)
    const body = await r.json() as any
    expect(body.scene).toBe('other')
    expect(body.grade.exposure_ev).toBe(0)
  })
})
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement routes**

```typescript
// backend/src/index.ts
import { Hono } from 'hono'
import { z } from 'zod'
import { CoachTipSchema, SceneAnalysisSchema, neutralGrade } from './schemas'
import { COACH_SYSTEM_PROMPT_V1, COLORIST_SYSTEM_PROMPT_V1 } from './prompts'
import { callClaudeVision, makeAnthropic } from './anthropic'
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

app.get('/', (c) => c.text('Cue backend'))

app.post('/coach', async (c) => {
  const ip = c.req.header('cf-connecting-ip') ?? 'anon'
  const limit = await take(c.env.RATELIMIT, ip, 'coach', COACH_LIMIT, WINDOW_MS)
  if (!limit.ok) {
    return c.json({ error: 'rate_limited' }, 429, { 'Retry-After': String(limit.retryAfterSec) })
  }

  const parse = RequestBody.safeParse(await c.req.json().catch(() => ({})))
  if (!parse.success) return c.json({ error: 'bad_body' }, 400)

  try {
    const raw = await callClaudeVision(makeAnthropic(c.env.ANTHROPIC_API_KEY), {
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
    const raw = await callClaudeVision(makeAnthropic(c.env.ANTHROPIC_API_KEY), {
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
```

- [ ] **Step 4: Run — expect PASS**

```bash
cd backend && npm test
```

Expected: all backend tests pass.

- [ ] **Step 5: Commit**

```bash
git add backend/src/index.ts backend/test/routes.test.ts
git commit -m "feat(backend): /coach and /grade routes with rate limiting and fallbacks"
```

---

## Phase 2 — iOS color grading core

> **Verification policy (Phase 2 onward):** these tasks cannot be compiled in this environment. Each task ends in "Commit". The user verifies after installing Xcode.

### Task 2.1: GradeParams + SceneAnalysis Codable models

**Files:**
- Create: `app/Cue/Color/GradeParams.swift`
- Create: `app/Cue/Models/SceneAnalysis.swift`
- Create: `app/Cue/Models/CoachTip.swift`
- Create: `app/Cue/Color/NeutralPreset.swift`

- [ ] **Step 1: GradeParams.swift**

```swift
// app/Cue/Color/GradeParams.swift
import Foundation

public struct HSLBand: Codable, Equatable, Sendable {
    public var hue: Double         // -30 ... +30
    public var saturation: Double  // -100 ... +100
    public var luminance: Double   // -100 ... +100

    public static let zero = HSLBand(hue: 0, saturation: 0, luminance: 0)
}

public struct HSLBands: Codable, Equatable, Sendable {
    public var red: HSLBand
    public var orange: HSLBand
    public var yellow: HSLBand
    public var green: HSLBand
    public var aqua: HSLBand
    public var blue: HSLBand
    public var purple: HSLBand
    public var magenta: HSLBand

    public static let zero = HSLBands(
        red: .zero, orange: .zero, yellow: .zero, green: .zero,
        aqua: .zero, blue: .zero, purple: .zero, magenta: .zero
    )
}

public struct GradeParams: Codable, Equatable, Sendable {
    public var exposure_ev: Double       // -2 ... +2
    public var contrast: Double          // -50 ... +50
    public var highlights: Double        // -100 ... +100
    public var shadows: Double           // -100 ... +100
    public var whites: Double
    public var blacks: Double
    public var saturation: Double        // -100 ... +100
    public var vibrance: Double          // -100 ... +100
    public var temperature: Double       // -100 ... +100
    public var tint: Double              // -100 ... +100
    public var hsl: HSLBands
    public var vignette_intensity: Double  // 0 ... 1
    public var vignette_radius: Double     // 0.5 ... 2

    public static let neutral = GradeParams(
        exposure_ev: 0, contrast: 0,
        highlights: 0, shadows: 0, whites: 0, blacks: 0,
        saturation: 0, vibrance: 0,
        temperature: 0, tint: 0,
        hsl: .zero,
        vignette_intensity: 0, vignette_radius: 1
    )

    /// Defensive clamp — backend already validates, but never trust the wire.
    public func clamped() -> GradeParams {
        var g = self
        g.exposure_ev       = g.exposure_ev.clamped(-2, 2)
        g.contrast          = g.contrast.clamped(-50, 50)
        g.highlights        = g.highlights.clamped(-100, 100)
        g.shadows           = g.shadows.clamped(-100, 100)
        g.whites            = g.whites.clamped(-100, 100)
        g.blacks            = g.blacks.clamped(-100, 100)
        g.saturation        = g.saturation.clamped(-100, 100)
        g.vibrance          = g.vibrance.clamped(-100, 100)
        g.temperature       = g.temperature.clamped(-100, 100)
        g.tint              = g.tint.clamped(-100, 100)
        g.vignette_intensity = g.vignette_intensity.clamped(0, 1)
        g.vignette_radius   = g.vignette_radius.clamped(0.5, 2)
        g.hsl = HSLBands(
            red: g.hsl.red.clamped(), orange: g.hsl.orange.clamped(),
            yellow: g.hsl.yellow.clamped(), green: g.hsl.green.clamped(),
            aqua: g.hsl.aqua.clamped(), blue: g.hsl.blue.clamped(),
            purple: g.hsl.purple.clamped(), magenta: g.hsl.magenta.clamped()
        )
        return g
    }
}

private extension HSLBand {
    func clamped() -> HSLBand {
        HSLBand(
            hue: hue.clamped(-30, 30),
            saturation: saturation.clamped(-100, 100),
            luminance: luminance.clamped(-100, 100)
        )
    }
}

private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { min(max(self, lo), hi) }
}
```

- [ ] **Step 2: SceneAnalysis.swift**

```swift
// app/Cue/Models/SceneAnalysis.swift
import Foundation

public enum Scene: String, Codable, Sendable {
    case portrait, group, food, landscape, urban, night, interior, product, pet, document, other
}

public enum Lighting: String, Codable, Sendable {
    case harsh_sun, golden_hour, overcast, shade, indoor_warm, indoor_cool, mixed, low_light, flash
}

public struct SceneAnalysis: Codable, Equatable, Sendable {
    public var scene: Scene
    public var lighting: Lighting
    public var rationale: String
    public var grade: GradeParams

    public static let neutralFallback = SceneAnalysis(
        scene: .other, lighting: .mixed,
        rationale: "默认参数(网络/分析失败)",
        grade: .neutral
    )
}
```

- [ ] **Step 3: CoachTip.swift**

```swift
// app/Cue/Models/CoachTip.swift
import Foundation

public enum CoachPriority: String, Codable, Sendable { case low, med, high }

public struct CoachTip: Codable, Equatable, Sendable {
    public var tip: String?
    public var priority: CoachPriority

    public static let silent = CoachTip(tip: nil, priority: .low)

    public var isWorthShowing: Bool {
        guard let tip, !tip.isEmpty else { return false }
        return priority == .med || priority == .high
    }
}
```

- [ ] **Step 4: NeutralPreset.swift** (re-exports for callsite clarity)

```swift
// app/Cue/Color/NeutralPreset.swift
import Foundation

public enum NeutralPreset {
    public static var grade: GradeParams { .neutral }
    public static var sceneAnalysis: SceneAnalysis { .neutralFallback }
}
```

- [ ] **Step 5: Commit**

```bash
git add app/Cue/Color/GradeParams.swift app/Cue/Color/NeutralPreset.swift \
        app/Cue/Models/SceneAnalysis.swift app/Cue/Models/CoachTip.swift
git commit -m "feat(ios): grade params, scene analysis, coach tip codable models"
```

---

### Task 2.2: HSL CIKernel (per-band hue/saturation/luminance)

**Files:**
- Create: `app/Cue/Color/HSLKernel.swift`
- Create: `app/Cue/Color/HSLKernel.ci.metal`

- [ ] **Step 1: Metal kernel source**

```metal
// app/Cue/Color/HSLKernel.ci.metal
#include <CoreImage/CoreImage.h>

using namespace metal;

extern "C" {
namespace coreimage {

// Helper: RGB → HSL (luminance) approximation in [0..1]
float3 rgb2hsl(float3 c) {
    float maxc = max(c.r, max(c.g, c.b));
    float minc = min(c.r, min(c.g, c.b));
    float l = (maxc + minc) * 0.5;
    float d = maxc - minc;
    float h = 0.0, s = 0.0;
    if (d > 1e-6) {
        s = l > 0.5 ? d / (2.0 - maxc - minc) : d / (maxc + minc);
        if (maxc == c.r)      h = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0);
        else if (maxc == c.g) h = (c.b - c.r) / d + 2.0;
        else                  h = (c.r - c.g) / d + 4.0;
        h /= 6.0;
    }
    return float3(h, s, l);
}

float hue2rgb(float p, float q, float t) {
    if (t < 0.0) t += 1.0;
    if (t > 1.0) t -= 1.0;
    if (t < 1.0/6.0) return p + (q - p) * 6.0 * t;
    if (t < 1.0/2.0) return q;
    if (t < 2.0/3.0) return p + (q - p) * (2.0/3.0 - t) * 6.0;
    return p;
}

float3 hsl2rgb(float3 hsl) {
    float h = hsl.x, s = hsl.y, l = hsl.z;
    if (s < 1e-6) return float3(l);
    float q = l < 0.5 ? l * (1.0 + s) : l + s - l * s;
    float p = 2.0 * l - q;
    return float3(
        hue2rgb(p, q, h + 1.0/3.0),
        hue2rgb(p, q, h),
        hue2rgb(p, q, h - 1.0/3.0)
    );
}

// 8 hue band centers (red, orange, yellow, green, aqua, blue, purple, magenta), normalized 0..1.
constant float bandCenters[8] = { 0.0, 0.0833, 0.1667, 0.3333, 0.5, 0.6667, 0.75, 0.8333 };

// Triangular weight for a single band on hue h.
float bandWeight(float h, int idx) {
    float c = bandCenters[idx];
    float d = abs(h - c);
    d = min(d, 1.0 - d);          // wrap
    float halfWidth = 1.0 / 16.0; // total = 8 bands, half-overlap at 1/16
    return clamp(1.0 - d / halfWidth, 0.0, 1.0);
}

// 24 floats: for each band, (hueShift[-1..1 = -180..180° but we use small 8.3% = ±30°],
// satMult, lumShift). We pass them as 8 packed float3 inside one float* buffer of size 24.
float4 hslAdjust(coreimage::sample_t pixel, float h0, float s0, float l0,
                 float h1, float s1, float l1,
                 float h2, float s2, float l2,
                 float h3, float s3, float l3,
                 float h4, float s4, float l4,
                 float h5, float s5, float l5,
                 float h6, float s6, float l6,
                 float h7, float s7, float l7) {
    float3 rgb = pixel.rgb;
    float3 hsl = rgb2hsl(rgb);

    float dh = 0, ds = 0, dl = 0;
    float h[8] = { h0, h1, h2, h3, h4, h5, h6, h7 };
    float s[8] = { s0, s1, s2, s3, s4, s5, s6, s7 };
    float l[8] = { l0, l1, l2, l3, l4, l5, l6, l7 };

    for (int i = 0; i < 8; i++) {
        float w = bandWeight(hsl.x, i);
        dh += w * h[i];
        ds += w * s[i];
        dl += w * l[i];
    }

    hsl.x = fract(hsl.x + dh);
    hsl.y = clamp(hsl.y * (1.0 + ds), 0.0, 1.0);
    hsl.z = clamp(hsl.z + dl, 0.0, 1.0);

    float3 outRgb = hsl2rgb(hsl);
    return float4(outRgb, pixel.a);
}

}
}
```

- [ ] **Step 2: Swift wrapper**

```swift
// app/Cue/Color/HSLKernel.swift
import CoreImage
import Foundation

public enum HSLKernel {
    /// Singleton kernel, loaded lazily from the .ci.metal blob.
    public static let kernel: CIColorKernel = {
        let url = Bundle.main.url(forResource: "HSLKernel.ci", withExtension: "metallib")
            ?? Bundle.main.url(forResource: "default.metallib", withExtension: nil)!
        let data = try! Data(contentsOf: url)
        return try! CIColorKernel(functionName: "hslAdjust", fromMetalLibraryData: data)
    }()

    /// Apply HSL bands to an image.
    public static func apply(to image: CIImage, hsl: HSLBands) -> CIImage {
        // Map UI ranges to kernel-native ranges.
        //   hue:        -30..+30 degrees → -30/360..+30/360 (normalized hue shift)
        //   saturation: -100..+100 → -1..+1 (multiplier delta)
        //   luminance:  -100..+100 → -0.25..+0.25 (additive)
        func pack(_ b: HSLBand) -> (Double, Double, Double) {
            (b.hue / 360.0, b.saturation / 100.0, b.luminance * 0.0025)
        }
        let bands = [hsl.red, hsl.orange, hsl.yellow, hsl.green,
                     hsl.aqua, hsl.blue, hsl.purple, hsl.magenta]
        let args: [CGFloat] = bands.flatMap { b -> [CGFloat] in
            let (h, s, l) = pack(b)
            return [CGFloat(h), CGFloat(s), CGFloat(l)]
        }
        return kernel.apply(extent: image.extent, arguments: [image] + args.map { $0 as Any }) ?? image
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add app/Cue/Color/HSLKernel.swift app/Cue/Color/HSLKernel.ci.metal
git commit -m "feat(ios): per-band HSL Core Image kernel (Metal)"
```

---

### Task 2.3: Core Image pipeline

**Files:**
- Create: `app/Cue/Color/CIPipeline.swift`

- [ ] **Step 1: Pipeline**

```swift
// app/Cue/Color/CIPipeline.swift
import CoreImage
import CoreImage.CIFilterBuiltins

public enum CIPipeline {

    /// Apply a GradeParams in spec-defined order. Returns a CIImage backed by GPU ops.
    public static func apply(_ raw: GradeParams, to input: CIImage) -> CIImage {
        let p = raw.clamped()
        var img = input

        // 1. Exposure
        if p.exposure_ev != 0 {
            let f = CIFilter.exposureAdjust()
            f.inputImage = img
            f.ev = Float(p.exposure_ev)
            img = f.outputImage ?? img
        }

        // 2. Highlights / Shadows
        if p.highlights != 0 || p.shadows != 0 {
            let f = CIFilter.highlightShadowAdjust()
            f.inputImage = img
            f.highlightAmount = Float(1.0 + p.highlights / 100.0 * -0.5) // negative pulls down
            f.shadowAmount    = Float(p.shadows / 100.0 * 0.6)           // positive lifts
            img = f.outputImage ?? img
        }

        // 3. Whites/Blacks/Contrast via tone curve
        let toneCurve = makeToneCurve(whites: p.whites, blacks: p.blacks, contrast: p.contrast)
        if let curve = toneCurve {
            let f = CIFilter.toneCurve()
            f.inputImage = img
            f.point0 = curve.p0
            f.point1 = curve.p1
            f.point2 = curve.p2
            f.point3 = curve.p3
            f.point4 = curve.p4
            img = f.outputImage ?? img
        }

        // 4. Temperature / Tint
        if p.temperature != 0 || p.tint != 0 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = img
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(
                x: 6500 + p.temperature * 20,    // ±2000K range
                y: p.tint * 0.5                  // ±50
            )
            img = f.outputImage ?? img
        }

        // 5. Saturation (global)
        if p.saturation != 0 {
            let f = CIFilter.colorControls()
            f.inputImage = img
            f.saturation = Float(1.0 + p.saturation / 100.0)
            img = f.outputImage ?? img
        }

        // 6. Vibrance
        if p.vibrance != 0 {
            let f = CIFilter.vibrance()
            f.inputImage = img
            f.amount = Float(p.vibrance / 100.0)
            img = f.outputImage ?? img
        }

        // 7. HSL per band
        if hasAnyHSL(p.hsl) {
            img = HSLKernel.apply(to: img, hsl: p.hsl)
        }

        // 8. Vignette
        if p.vignette_intensity > 0 {
            let f = CIFilter.vignetteEffect()
            f.inputImage = img
            f.intensity = Float(p.vignette_intensity)
            f.radius    = Float(p.vignette_radius * Double(min(img.extent.width, img.extent.height)) * 0.5)
            f.center    = CGPoint(x: img.extent.midX, y: img.extent.midY)
            img = f.outputImage ?? img
        }

        return img
    }

    // MARK: - Tone curve

    private struct ToneCurve {
        let p0: CGPoint
        let p1: CGPoint
        let p2: CGPoint
        let p3: CGPoint
        let p4: CGPoint
    }

    private static func makeToneCurve(whites: Double, blacks: Double, contrast: Double) -> ToneCurve? {
        if whites == 0 && blacks == 0 && contrast == 0 { return nil }
        // Endpoints
        let x0: CGFloat = max(0, CGFloat(-blacks / 100.0 * 0.25))      // blacks raises floor or pushes down
        let y0: CGFloat = blacks >= 0 ? 0 : CGFloat(-blacks / 100.0 * 0.15)
        let x4: CGFloat = min(1, 1 + CGFloat(whites / 100.0 * 0.15))
        let y4: CGFloat = whites >= 0 ? 1 : 1 + CGFloat(whites / 100.0 * 0.25)

        // S-curve from contrast: pull 0.25 down, push 0.75 up
        let c = CGFloat(contrast / 100.0) * 0.20
        let p1 = CGPoint(x: 0.25, y: max(0, 0.25 - c))
        let p2 = CGPoint(x: 0.5, y: 0.5)
        let p3 = CGPoint(x: 0.75, y: min(1, 0.75 + c))

        return ToneCurve(
            p0: CGPoint(x: x0, y: y0),
            p1: p1, p2: p2, p3: p3,
            p4: CGPoint(x: x4, y: y4)
        )
    }

    private static func hasAnyHSL(_ b: HSLBands) -> Bool {
        let all: [HSLBand] = [b.red, b.orange, b.yellow, b.green, b.aqua, b.blue, b.purple, b.magenta]
        return all.contains { $0.hue != 0 || $0.saturation != 0 || $0.luminance != 0 }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/Cue/Color/CIPipeline.swift
git commit -m "feat(ios): core image grading pipeline (exposure→hsl→vignette)"
```

---

### Task 2.4: Renderer + photo writer

**Files:**
- Create: `app/Cue/Color/PhotoRenderer.swift`

- [ ] **Step 1: Implementation**

```swift
// app/Cue/Color/PhotoRenderer.swift
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Photos
import UIKit

public enum PhotoRendererError: Error {
    case cgImageFailed
    case jpegEncodeFailed
    case photoLibraryDenied
    case saveFailed(Error)
}

public final class PhotoRenderer {
    private let context: CIContext

    public init() {
        self.context = CIContext(options: [
            .useSoftwareRenderer: false,
            .cacheIntermediates: false,
            .name: "cue.renderer",
        ])
    }

    /// Render a CIImage to a JPEG `Data`.
    public func renderToJPEG(_ image: CIImage, quality: CGFloat = 0.92) throws -> Data {
        guard let cg = context.createCGImage(image, from: image.extent) else {
            throw PhotoRendererError.cgImageFailed
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw PhotoRendererError.jpegEncodeFailed
        }
        let opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, cg, opts as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw PhotoRendererError.jpegEncodeFailed
        }
        return data as Data
    }

    /// Save a JPEG to the user's Photos library.
    public func saveToPhotoLibrary(_ jpeg: Data) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited: break
        case .denied, .restricted: throw PhotoRendererError.photoLibraryDenied
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            if granted != .authorized && granted != .limited {
                throw PhotoRendererError.photoLibraryDenied
            }
        @unknown default: throw PhotoRendererError.photoLibraryDenied
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: jpeg, options: nil)
            }
        } catch {
            throw PhotoRendererError.saveFailed(error)
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/Cue/Color/PhotoRenderer.swift
git commit -m "feat(ios): CIImage → JPEG render + PHPhotoLibrary save"
```

---

## Phase 3 — iOS backend client

### Task 3.1: ImageEncoder

**Files:**
- Create: `app/Cue/LLM/ImageEncoder.swift`

- [ ] **Step 1: Implementation**

```swift
// app/Cue/LLM/ImageEncoder.swift
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import UIKit

public enum ImageEncoder {

    /// Downsample a CIImage so longer side = `maxSide`, encode JPEG at `quality`,
    /// return base64 string (no data URL prefix).
    public static func downsampledBase64(from image: CIImage, maxSide: CGFloat, quality: CGFloat) -> String? {
        let extent = image.extent
        let longSide = max(extent.width, extent.height)
        let scale = min(1.0, maxSide / longSide)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, cg, [
            kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return (data as Data).base64EncodedString()
    }

    /// Convenience overload for a CVPixelBuffer (preview frame).
    public static func downsampledBase64(from pixelBuffer: CVPixelBuffer, maxSide: CGFloat, quality: CGFloat) -> String? {
        downsampledBase64(from: CIImage(cvPixelBuffer: pixelBuffer), maxSide: maxSide, quality: quality)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/Cue/LLM/ImageEncoder.swift
git commit -m "feat(ios): downsample+jpeg+base64 image encoder"
```

---

### Task 3.2: BackendClient

**Files:**
- Create: `app/Cue/LLM/BackendClient.swift`

- [ ] **Step 1: Implementation**

```swift
// app/Cue/LLM/BackendClient.swift
import Foundation

public enum BackendError: Error {
    case badResponse(Int)
    case decodeFailed(Error)
    case rateLimited(retryAfter: TimeInterval)
}

public final class BackendClient {
    /// EDIT THIS after deploying the Worker.
    public static var baseURL = URL(string: "https://cue-backend.YOUR-SUBDOMAIN.workers.dev")!

    public init() {}

    public func coach(imageB64: String) async throws -> CoachTip {
        try await post(path: "/coach", imageB64: imageB64, timeout: 1.5, as: CoachTip.self)
    }

    public func grade(imageB64: String) async throws -> SceneAnalysis {
        try await post(path: "/grade", imageB64: imageB64, timeout: 4.0, as: SceneAnalysis.self)
    }

    private func post<T: Decodable>(path: String, imageB64: String, timeout: TimeInterval, as: T.Type) async throws -> T {
        var req = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
                     forHTTPHeaderField: "X-Client-Version")
        req.timeoutInterval = timeout

        struct Body: Encodable {
            let image_b64: String
            let client_version: String
        }
        let body = Body(
            image_b64: imageB64,
            client_version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw BackendError.badResponse(-1) }
        if http.statusCode == 429 {
            let retry = TimeInterval(http.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
            throw BackendError.rateLimited(retryAfter: retry)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.badResponse(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw BackendError.decodeFailed(error)
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/Cue/LLM/BackendClient.swift
git commit -m "feat(ios): backend client for /coach and /grade"
```

---

## Phase 4 — iOS on-device CV

### Task 4.1: OnDeviceCV

**Files:**
- Create: `app/Cue/Compose/OnDeviceCV.swift`

- [ ] **Step 1: Implementation**

```swift
// app/Cue/Compose/OnDeviceCV.swift
import Vision
import CoreMotion
import CoreImage
import Combine
import UIKit

public struct ComposeState: Equatable {
    public var subjectBox: CGRect?     // normalized to [0,1] in image coords
    public var faceBoxes: [CGRect]     // normalized
    public var horizonDegrees: Double  // device roll relative to ground, -180..180

    public static let initial = ComposeState(subjectBox: nil, faceBoxes: [], horizonDegrees: 0)
}

public final class OnDeviceCV: ObservableObject {
    @Published public private(set) var state: ComposeState = .initial

    private let motion = CMMotionManager()
    private let saliencyQ = DispatchQueue(label: "cue.cv.saliency", qos: .userInitiated)
    private let faceQ     = DispatchQueue(label: "cue.cv.face",     qos: .userInitiated)
    private var lastSaliencyAt: TimeInterval = 0
    private var lastFaceAt: TimeInterval = 0
    private let cvHz: TimeInterval = 1.0 / 10.0  // 10 Hz throttle

    public init() {
        startMotion()
    }

    deinit { motion.stopDeviceMotionUpdates() }

    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] dm, _ in
            guard let self, let dm else { return }
            // Convert roll (radians, around z-axis in portrait) to degrees.
            let deg = dm.attitude.roll * 180.0 / .pi
            DispatchQueue.main.async { self.state.horizonDegrees = deg }
        }
    }

    /// Feed each preview frame here. Internally throttles to 10 Hz.
    public func ingest(pixelBuffer: CVPixelBuffer) {
        let now = CACurrentMediaTime()
        if now - lastSaliencyAt > cvHz {
            lastSaliencyAt = now
            runSaliency(pixelBuffer: pixelBuffer)
        }
        if now - lastFaceAt > cvHz {
            lastFaceAt = now
            runFaces(pixelBuffer: pixelBuffer)
        }
    }

    private func runSaliency(pixelBuffer: CVPixelBuffer) {
        saliencyQ.async { [weak self] in
            let req = VNGenerateAttentionBasedSaliencyImageRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try handler.perform([req])
                guard let result = req.results?.first, let salient = result.salientObjects?.first else { return }
                DispatchQueue.main.async { self?.state.subjectBox = salient.boundingBox }
            } catch { /* swallow */ }
        }
    }

    private func runFaces(pixelBuffer: CVPixelBuffer) {
        faceQ.async { [weak self] in
            let req = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try handler.perform([req])
                let boxes = (req.results ?? []).map(\.boundingBox)
                DispatchQueue.main.async { self?.state.faceBoxes = boxes }
            } catch { /* swallow */ }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/Cue/Compose/OnDeviceCV.swift
git commit -m "feat(ios): on-device CV (saliency + faces + horizon)"
```

---

### Task 4.2: CoachThrottler

**Files:**
- Create: `app/Cue/Compose/CoachThrottler.swift`

- [ ] **Step 1: Implementation**

```swift
// app/Cue/Compose/CoachThrottler.swift
import Foundation
import CoreImage

@MainActor
public final class CoachThrottler: ObservableObject {
    @Published public private(set) var currentTip: CoachTip = .silent
    @Published public private(set) var lastShownAt: Date?

    private let client: BackendClient
    private let intervalSeconds: TimeInterval = 2.0
    private let bannerHoldSeconds: TimeInterval = 4.0
    private var inFlight = false
    private var lastCallAt: Date = .distantPast
    private var lastTipText: String?
    private var coachDisabled = false  // set true on rate-limit

    public init(client: BackendClient) {
        self.client = client
    }

    /// Try to send a coach call; no-op if too recent / in-flight / disabled.
    public func tick(pixelBuffer: CVPixelBuffer) {
        guard !coachDisabled, !inFlight else { return }
        let now = Date()
        guard now.timeIntervalSince(lastCallAt) >= intervalSeconds else { return }
        guard let b64 = ImageEncoder.downsampledBase64(from: pixelBuffer, maxSide: 1024, quality: 0.6) else { return }
        inFlight = true
        lastCallAt = now
        Task { @MainActor [weak self] in
            defer { self?.inFlight = false }
            guard let self else { return }
            do {
                let tip = try await self.client.coach(imageB64: b64)
                self.publish(tip)
            } catch BackendError.rateLimited {
                self.coachDisabled = true
            } catch {
                // network blip — ignore, try next tick
            }
        }
    }

    private func publish(_ tip: CoachTip) {
        guard tip.isWorthShowing else {
            // Auto-fade if last shown is older than hold window
            if let shown = lastShownAt, Date().timeIntervalSince(shown) > bannerHoldSeconds {
                currentTip = .silent
            }
            return
        }
        if tip.tip == lastTipText { return }   // dedup
        lastTipText = tip.tip
        currentTip = tip
        lastShownAt = Date()
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/Cue/Compose/CoachThrottler.swift
git commit -m "feat(ios): coach throttler (2s cadence, dedup, in-flight guard, rate-limit pause)"
```

---

### Task 4.3: CompositionOverlay

**Files:**
- Create: `app/Cue/Compose/CompositionOverlay.swift`

- [ ] **Step 1: SwiftUI overlay**

```swift
// app/Cue/Compose/CompositionOverlay.swift
import SwiftUI

public struct CompositionOverlay: View {
    let state: ComposeState
    let coachTip: CoachTip
    let showGrid: Bool

    public init(state: ComposeState, coachTip: CoachTip, showGrid: Bool = true) {
        self.state = state
        self.coachTip = coachTip
        self.showGrid = showGrid
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                if showGrid { gridLines.opacity(0.35) }
                horizonLine
                if let box = state.subjectBox {
                    boundingBox(box, in: geo.size, color: .yellow)
                }
                ForEach(Array(state.faceBoxes.enumerated()), id: \.offset) { _, box in
                    boundingBox(box, in: geo.size, color: .green)
                }
                VStack {
                    Spacer()
                    if let tip = coachTip.tip, coachTip.isWorthShowing {
                        coachBanner(tip)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 140)
                .animation(.easeInOut(duration: 0.25), value: coachTip)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: 3x3 grid

    private var gridLines: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: w/3, y: 0));     p.addLine(to: CGPoint(x: w/3, y: h))
                p.move(to: CGPoint(x: 2*w/3, y: 0));   p.addLine(to: CGPoint(x: 2*w/3, y: h))
                p.move(to: CGPoint(x: 0, y: h/3));     p.addLine(to: CGPoint(x: w, y: h/3))
                p.move(to: CGPoint(x: 0, y: 2*h/3));   p.addLine(to: CGPoint(x: w, y: 2*h/3))
            }
            .stroke(Color.white, lineWidth: 0.5)
        }
    }

    // MARK: horizon

    private var horizonLine: some View {
        GeometryReader { geo in
            let deg = state.horizonDegrees
            // Hide if user is intentionally tilted (>30°)
            let visible = abs(deg) < 30
            Rectangle()
                .fill(abs(deg) < 1.5 ? Color.green : Color.yellow)
                .frame(width: geo.size.width * 0.5, height: 1.5)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .rotationEffect(.degrees(deg))
                .opacity(visible ? 0.8 : 0)
        }
    }

    // MARK: bbox

    private func boundingBox(_ norm: CGRect, in size: CGSize, color: Color) -> some View {
        // Vision boxes are in [0,1] with origin at bottom-left.
        let r = CGRect(
            x: norm.minX * size.width,
            y: (1 - norm.maxY) * size.height,
            width: norm.width * size.width,
            height: norm.height * size.height
        )
        return Rectangle()
            .stroke(color.opacity(0.9), lineWidth: 1.5)
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
    }

    // MARK: coach banner

    private func coachBanner(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial.opacity(0.6))
            .background(Color.black.opacity(0.35))
            .clipShape(Capsule())
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/Cue/Compose/CompositionOverlay.swift
git commit -m "feat(ios): composition overlay (grid + horizon + subject/face boxes + coach banner)"
```

---

## Phase 5 — iOS camera

### Task 5.1: CameraSession

**Files:**
- Create: `app/Cue/Camera/CameraSession.swift`

- [ ] **Step 1: Implementation**

```swift
// app/Cue/Camera/CameraSession.swift
import AVFoundation
import CoreImage
import Combine
import UIKit

public protocol CameraSessionDelegate: AnyObject {
    func cameraDidEmitPreview(_ pixelBuffer: CVPixelBuffer)
    func cameraDidCapturePhoto(_ ciImage: CIImage)
    func cameraDidFail(_ error: Error)
}

public enum CameraError: Error {
    case permissionDenied
    case noBackCamera
    case configureFailed
}

public final class CameraSession: NSObject {
    public let session = AVCaptureSession()
    public weak var delegate: CameraSessionDelegate?

    private let sessionQueue = DispatchQueue(label: "cue.camera.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?

    public override init() {
        super.init()
    }

    public func configure() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            do {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    throw CameraError.noBackCamera
                }
                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input) else { throw CameraError.configureFailed }
                self.session.addInput(input)
                self.videoDeviceInput = input

                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                self.videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "cue.camera.video"))
                guard self.session.canAddOutput(self.videoOutput) else { throw CameraError.configureFailed }
                self.session.addOutput(self.videoOutput)
                if let conn = self.videoOutput.connection(with: .video) {
                    conn.videoOrientation = .portrait
                }

                guard self.session.canAddOutput(self.photoOutput) else { throw CameraError.configureFailed }
                self.session.addOutput(self.photoOutput)
                self.photoOutput.maxPhotoQualityPrioritization = .quality

                self.session.commitConfiguration()
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.delegate?.cameraDidFail(error) }
            }
        }
    }

    public func start() {
        sessionQueue.async { [weak self] in
            if let s = self?.session, !s.isRunning { s.startRunning() }
        }
    }

    public func stop() {
        sessionQueue.async { [weak self] in
            if let s = self?.session, s.isRunning { s.stopRunning() }
        }
    }

    public func capture() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            settings.flashMode = .auto
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    public static func requestAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }
}

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        delegate?.cameraDidEmitPreview(pb)
    }
}

extension CameraSession: AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            DispatchQueue.main.async { self.delegate?.cameraDidFail(error) }
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let ci = CIImage(data: data) else {
            DispatchQueue.main.async { self.delegate?.cameraDidFail(CameraError.configureFailed) }
            return
        }
        DispatchQueue.main.async { self.delegate?.cameraDidCapturePhoto(ci) }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/Cue/Camera/CameraSession.swift
git commit -m "feat(ios): AVCaptureSession wrapper (preview + still photo)"
```

---

### Task 5.2: CameraPreviewView

**Files:**
- Create: `app/Cue/Camera/CameraPreviewView.swift`

- [ ] **Step 1: UIViewRepresentable**

```swift
// app/Cue/Camera/CameraPreviewView.swift
import SwiftUI
import AVFoundation

public struct CameraPreviewView: UIViewRepresentable {
    public let session: AVCaptureSession

    public init(session: AVCaptureSession) { self.session = session }

    public func makeUIView(context: Context) -> PreviewLayerView {
        let v = PreviewLayerView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }
    public func updateUIView(_ uiView: PreviewLayerView, context: Context) {}

    public final class PreviewLayerView: UIView {
        public override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        public var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/Cue/Camera/CameraPreviewView.swift
git commit -m "feat(ios): SwiftUI camera preview UIViewRepresentable"
```

---

## Phase 6 — iOS app shell + wiring

### Task 6.1: App entry + RootView + PermissionGate

**Files:**
- Create: `app/Cue/App/CueApp.swift`
- Create: `app/Cue/App/RootView.swift`
- Create: `app/Cue/Views/PermissionGate.swift`

- [ ] **Step 1: CueApp**

```swift
// app/Cue/App/CueApp.swift
import SwiftUI

@main
struct CueApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .statusBar(hidden: true)
        }
    }
}
```

- [ ] **Step 2: PermissionGate**

```swift
// app/Cue/Views/PermissionGate.swift
import SwiftUI
import AVFoundation
import Photos

public struct PermissionGate<Content: View>: View {
    @State private var cameraGranted = false
    @State private var photosGranted = false
    @State private var checked = false
    let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        Group {
            if !checked {
                ProgressView().task { await check() }
            } else if cameraGranted {
                content()
            } else {
                deniedView
            }
        }
    }

    private func check() async {
        cameraGranted = await CameraSession.requestAuthorization()
        let phStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if phStatus == .notDetermined {
            let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            photosGranted = granted == .authorized || granted == .limited
        } else {
            photosGranted = phStatus == .authorized || phStatus == .limited
        }
        checked = true
    }

    private var deniedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.slash.fill")
                .font(.system(size: 64))
            Text("需要相机权限")
                .font(.title2.weight(.semibold))
            Text("Cue 需要相机来拍摄并自动调色。\n请在系统设置中开启相机权限。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button("打开系统设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
}
```

- [ ] **Step 3: RootView (wiring)**

```swift
// app/Cue/App/RootView.swift
import SwiftUI
import CoreImage
import AVFoundation

@MainActor
final class RootViewModel: ObservableObject, CameraSessionDelegate {
    @Published var compose = ComposeState.initial
    @Published var coachTip: CoachTip = .silent
    @Published var beforeAfter: (before: CGImage, after: CGImage)?
    @Published var statusBanner: String?
    @Published var isProcessing = false

    let camera = CameraSession()
    let cv = OnDeviceCV()
    let client = BackendClient()
    lazy var throttler = CoachThrottler(client: client)
    let renderer = PhotoRenderer()

    init() {
        camera.delegate = self
        camera.configure()
    }

    func start() { camera.start() }
    func stop()  { camera.stop() }
    func capture() { camera.capture() }

    // MARK: CameraSessionDelegate

    nonisolated func cameraDidEmitPreview(_ pixelBuffer: CVPixelBuffer) {
        let buffer = pixelBuffer
        Task { @MainActor in
            self.cv.ingest(pixelBuffer: buffer)
            self.compose = self.cv.state
            self.throttler.tick(pixelBuffer: buffer)
            self.coachTip = self.throttler.currentTip
        }
    }

    nonisolated func cameraDidCapturePhoto(_ ciImage: CIImage) {
        Task { @MainActor in
            await self.process(captured: ciImage)
        }
    }

    nonisolated func cameraDidFail(_ error: Error) {
        Task { @MainActor in self.statusBanner = "相机错误: \(error.localizedDescription)" }
    }

    private func process(captured: CIImage) async {
        isProcessing = true
        defer { isProcessing = false }

        // 1. Compute base64 thumbnail for analysis (off the main actor).
        let b64 = await Task.detached(priority: .userInitiated) {
            ImageEncoder.downsampledBase64(from: captured, maxSide: 1024, quality: 0.85)
        }.value

        // 2. Call grader (with fallback on any failure).
        let analysis: SceneAnalysis
        if let b64 {
            do {
                analysis = try await client.grade(imageB64: b64)
            } catch {
                statusBanner = "调色服务离线,已使用默认参数。"
                analysis = NeutralPreset.sceneAnalysis
            }
        } else {
            statusBanner = "图像编码失败,已使用默认参数。"
            analysis = NeutralPreset.sceneAnalysis
        }

        // 3. Apply grade via Core Image (off main).
        let result = await Task.detached(priority: .userInitiated) { [renderer] in
            let graded = CIPipeline.apply(analysis.grade, to: captured)
            let originalCG = renderer.toCGImage(captured)
            let gradedCG   = renderer.toCGImage(graded)
            let jpegData   = try? renderer.renderToJPEG(graded)
            return (originalCG, gradedCG, jpegData)
        }.value

        if let before = result.0, let after = result.1 {
            beforeAfter = (before, after)
        }
        if let jpeg = result.2 {
            do { try await renderer.saveToPhotoLibrary(jpeg) }
            catch { statusBanner = "保存到相册失败。" }
        }

        // Auto-dismiss before/after after 3s.
        Task { try? await Task.sleep(nanoseconds: 3_000_000_000); beforeAfter = nil }
    }
}

public struct RootView: View {
    @StateObject private var vm = RootViewModel()

    public init() {}

    public var body: some View {
        PermissionGate {
            ZStack {
                CameraPreviewView(session: vm.camera.session)
                    .ignoresSafeArea()

                CompositionOverlay(state: vm.compose, coachTip: vm.coachTip)
                    .ignoresSafeArea()

                if let (before, after) = vm.beforeAfter {
                    BeforeAfterReveal(before: before, after: after)
                        .ignoresSafeArea()
                }

                VStack {
                    if let s = vm.statusBanner {
                        Text(s).font(.footnote).padding(8)
                            .background(.black.opacity(0.6)).clipShape(Capsule())
                            .foregroundStyle(.white).padding(.top, 60)
                    }
                    Spacer()
                    shutterButton
                        .padding(.bottom, 32)
                }
                .ignoresSafeArea(edges: .top)
            }
            .onAppear { vm.start() }
            .onDisappear { vm.stop() }
        }
    }

    private var shutterButton: some View {
        Button(action: { vm.capture() }) {
            ZStack {
                Circle().stroke(Color.white, lineWidth: 4).frame(width: 76, height: 76)
                Circle().fill(Color.white).frame(width: 64, height: 64)
                if vm.isProcessing {
                    ProgressView().tint(.black)
                }
            }
        }
        .disabled(vm.isProcessing)
    }
}

private extension PhotoRenderer {
    func toCGImage(_ image: CIImage) -> CGImage? {
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        return ctx.createCGImage(image, from: image.extent)
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add app/Cue/App/CueApp.swift app/Cue/App/RootView.swift app/Cue/Views/PermissionGate.swift
git commit -m "feat(ios): app entry, permission gate, root viewmodel wiring camera→cv→llm→ci→photos"
```

---

### Task 6.2: BeforeAfterReveal

**Files:**
- Create: `app/Cue/Views/BeforeAfterReveal.swift`

- [ ] **Step 1: Reveal animation**

```swift
// app/Cue/Views/BeforeAfterReveal.swift
import SwiftUI

public struct BeforeAfterReveal: View {
    let before: CGImage
    let after: CGImage
    @State private var revealed = false

    public init(before: CGImage, after: CGImage) {
        self.before = before
        self.after = after
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                Image(decorative: before, scale: 1, orientation: .up)
                    .resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                Image(decorative: after, scale: 1, orientation: .up)
                    .resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .mask(
                        Rectangle()
                            .frame(width: revealed ? geo.size.width : 0)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    )
            }
            .overlay(alignment: .top) {
                Text(revealed ? "after" : "before").font(.caption.weight(.medium))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.black.opacity(0.5)).clipShape(Capsule())
                    .foregroundStyle(.white)
                    .padding(.top, 60)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).delay(0.2)) {
                    revealed = true
                }
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/Cue/Views/BeforeAfterReveal.swift
git commit -m "feat(ios): before→after reveal animation"
```

---

## Phase 7 — Xcode project file + Info.plist + assets

### Task 7.1: xcodegen project.yml

**Files:**
- Create: `app/project.yml`
- Create: `app/Cue/Resources/Info.plist`
- Create: `app/Cue/Resources/Assets.xcassets/Contents.json`
- Create: `app/Cue/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `app/Cue/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`

- [ ] **Step 1: project.yml**

```yaml
# app/project.yml
name: Cue
options:
  bundleIdPrefix: com.cue
  deploymentTarget:
    iOS: "17.0"
  developmentLanguage: zh-Hans

settings:
  base:
    MARKETING_VERSION: "1.0.0"
    CURRENT_PROJECT_VERSION: "1"
    SWIFT_VERSION: "5.10"
    IPHONEOS_DEPLOYMENT_TARGET: "17.0"
    TARGETED_DEVICE_FAMILY: "1"   # iPhone only
    SUPPORTS_MACCATALYST: NO
    ENABLE_USER_SCRIPT_SANDBOXING: NO

targets:
  Cue:
    type: application
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: Cue
    info:
      path: Cue/Resources/Info.plist
      properties:
        CFBundleDisplayName: Cue
        UILaunchScreen: {}
        UIRequiresFullScreen: YES
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
        NSCameraUsageDescription: "Cue 需要相机来拍摄并实时给出构图与调色建议。"
        NSPhotoLibraryAddUsageDescription: "Cue 将自动调色后的照片保存到你的相册。"
        ITSAppUsesNonExemptEncryption: false
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.cue.app
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        DEVELOPMENT_TEAM: ""    # set in Xcode
    resources:
      - path: Cue/Resources/Assets.xcassets

  CueTests:
    type: bundle.unit-test
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: CueTests
    dependencies:
      - target: Cue
```

- [ ] **Step 2: Info.plist** (xcodegen merges these into a generated plist; we still want a placeholder)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```

- [ ] **Step 3: Assets.xcassets bootstrap**

```json
// app/Cue/Resources/Assets.xcassets/Contents.json
{
  "info" : { "author" : "xcode", "version" : 1 }
}
```

```json
// app/Cue/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json
{
  "images" : [
    { "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

```json
// app/Cue/Resources/Assets.xcassets/AccentColor.colorset/Contents.json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0.302", "green" : "0.169", "red" : "0.969" }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 4: Generate project**

```bash
cd app && xcodegen generate
ls Cue.xcodeproj
```

Expected: `Cue.xcodeproj` directory exists.

- [ ] **Step 5: Commit**

```bash
git add app/project.yml app/Cue/Resources/
git commit -m "build(ios): xcodegen project definition + Info.plist + assets bootstrap"
```

---

### Task 7.2: Wire Metal kernel build phase

**Files:**
- Modify: `app/project.yml`

- [ ] **Step 1: Add Metal source to target**

The `.ci.metal` file at `app/Cue/Color/HSLKernel.ci.metal` is picked up by xcodegen's `sources:` (recursive). Xcode auto-compiles `.metal` into the default Metal library at `default.metallib`. The Swift loader in `HSLKernel.swift` already falls back to `default.metallib`. No further change needed beyond xcodegen including the path.

Verify the path is included:

```bash
cd app && xcodegen generate
grep -c 'HSLKernel.ci.metal' Cue.xcodeproj/project.pbxproj
```

Expected: `1` or more (file referenced).

- [ ] **Step 2: Commit (no diff if grep passed)**

If grep returned 0, edit `project.yml` to explicitly add:

```yaml
    sources:
      - path: Cue
      - path: Cue/Color/HSLKernel.ci.metal
        type: file
```

Otherwise, no commit needed — proceed.

---

## Phase 8 — iOS tests (deferred verification)

### Task 8.1: GradeParams round-trip tests

**Files:**
- Create: `app/CueTests/GradeParamsTests.swift`

- [ ] **Step 1: Test file**

```swift
// app/CueTests/GradeParamsTests.swift
import Testing
import Foundation
@testable import Cue

@Suite("GradeParams") struct GradeParamsTests {

    @Test func neutralRoundTrip() throws {
        let n = GradeParams.neutral
        let data = try JSONEncoder().encode(n)
        let back = try JSONDecoder().decode(GradeParams.self, from: data)
        #expect(back == n)
    }

    @Test func clampOutOfRange() {
        var g = GradeParams.neutral
        g.exposure_ev = 999
        g.hsl.red.hue = 999
        let c = g.clamped()
        #expect(c.exposure_ev == 2)
        #expect(c.hsl.red.hue == 30)
    }

    @Test func decodesFullSceneAnalysis() throws {
        let json = """
        {
          "scene":"portrait","lighting":"golden_hour","rationale":"warm",
          "grade":{
            "exposure_ev":0.1,"contrast":5,"highlights":-20,"shadows":15,
            "whites":0,"blacks":-5,"saturation":0,"vibrance":10,
            "temperature":5,"tint":0,
            "hsl":{
              "red":{"hue":0,"saturation":-5,"luminance":0},
              "orange":{"hue":0,"saturation":0,"luminance":0},
              "yellow":{"hue":0,"saturation":0,"luminance":0},
              "green":{"hue":0,"saturation":0,"luminance":0},
              "aqua":{"hue":0,"saturation":0,"luminance":0},
              "blue":{"hue":0,"saturation":0,"luminance":0},
              "purple":{"hue":0,"saturation":0,"luminance":0},
              "magenta":{"hue":0,"saturation":0,"luminance":0}
            },
            "vignette_intensity":0,"vignette_radius":1
          }
        }
        """.data(using: .utf8)!
        let sa = try JSONDecoder().decode(SceneAnalysis.self, from: json)
        #expect(sa.scene == .portrait)
        #expect(sa.lighting == .golden_hour)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/CueTests/GradeParamsTests.swift
git commit -m "test(ios): GradeParams round-trip + clamp + scene analysis decode"
```

---

### Task 8.2: CIPipeline smoke test

**Files:**
- Create: `app/CueTests/CIPipelineTests.swift`

- [ ] **Step 1: Test**

```swift
// app/CueTests/CIPipelineTests.swift
import Testing
import CoreImage
@testable import Cue

@Suite("CIPipeline") struct CIPipelineTests {

    @Test func neutralIsIdentityShape() {
        let input = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        let out = CIPipeline.apply(.neutral, to: input)
        #expect(out.extent.width == 100)
        #expect(out.extent.height == 100)
    }

    @Test func extremeExposureCompiles() {
        var g = GradeParams.neutral
        g.exposure_ev = 1.5
        let input = CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
        let out = CIPipeline.apply(g, to: input)
        #expect(out.extent.width == 32)
    }

    @Test func vignetteAppliesAtNonZero() {
        var g = GradeParams.neutral
        g.vignette_intensity = 0.5
        let input = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let out = CIPipeline.apply(g, to: input)
        // Just verify the chain doesn't crash and produces an image.
        #expect(out.extent.width == 64)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/CueTests/CIPipelineTests.swift
git commit -m "test(ios): CIPipeline smoke tests (shape preservation, no crash)"
```

---

## Phase 9 — Final delivery polish

### Task 9.1: Final README pass

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README to include backend URL editing step**

Re-read `README.md` from Task 0.1. Verify the steps still apply. If anything in this plan changed (file paths, env names), update README accordingly. No code changes if already accurate.

- [ ] **Step 2: Commit (if changed)**

```bash
git diff --quiet README.md || git commit -am "docs: README accuracy pass after implementation"
```

---

### Task 9.2: Generate Xcode project + sanity-check structure

- [ ] **Step 1: Re-run xcodegen**

```bash
cd /Users/blink/project/cue/app && xcodegen generate
```

Expected: regenerates `Cue.xcodeproj` without errors.

- [ ] **Step 2: List final tree**

```bash
cd /Users/blink/project/cue && find . -type f -not -path './.git/*' -not -path '*/node_modules/*' -not -path '*/.wrangler/*' -not -path '*xcuserdata*' | sort
```

Expected: shows the project tree matching spec §12.

- [ ] **Step 3: Final commit (if xcodeproj wasn't ignored)**

The `.gitignore` excludes `*.xcodeproj`, so this generates locally without polluting git.

```bash
git status
```

Expected: working tree clean (xcodeproj untracked, ignored).

---

## Self-review

**Spec coverage:**
- §1 Product → Tasks 6.1, 6.2 (camera + capture + grade + save flow)
- §2 User flow → Tasks 5.1 (camera), 4.1–4.3 (compose), 6.1 (wiring)
- §3 Architecture → Phase 1 (backend), Phases 2–6 (iOS)
- §4 Color grading data model → Task 2.1 (Codable mirror), Task 1.2 (Zod mirror)
- §5 LLM contracts → Task 1.3 (prompts), Task 1.4 (anthropic), Task 1.6 (routes)
- §6 Core Image pipeline → Tasks 2.2 (HSL kernel), 2.3 (pipeline), 2.4 (renderer)
- §7 On-device CV → Task 4.1
- §8 Backend → Phase 1 entire
- §9 Privacy → README + Info.plist usage descriptions + backend logs only (Task 1.6)
- §10 Error handling → Task 1.6 (fallbacks, 429), Task 6.1 (banners)
- §11 Testing → Phase 1 tests + Task 8.1/8.2
- §12 Project structure → entire plan adheres
- §13 Non-goals → respected (no IAP, no auth, no presets)
- §14 Open decisions → deferred as documented

**Placeholder scan:** None. All "EDIT THIS" comments are user-action markers (deploy URL, KV ID, signing team) — these are real configuration steps documented in README, not unfinished code.

**Type consistency:** GradeParams field names match across Zod schema (snake_case), Swift Codable (snake_case via property names), TS type. SceneAnalysis enum values match. HSL band names match in 3 places: Swift `HSLBands`, Zod `Object.fromEntries(HSL_BANDS.map(...))`, Metal kernel `bandCenters` array order.

---

## Execution handoff

Per the user's instruction "我只要最后结果", we will execute this plan with **subagent-driven-development** without prompting for execution-mode choice. Subagent-driven gives per-task review and parallelism where safe.

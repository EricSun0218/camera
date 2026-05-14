# Auteur — Design Spec

**Date:** 2026-05-13
**Status:** v1 — pre-implementation
**Project root:** `~/project/auteur`

## 1. Product

**Auteur** is an iOS camera app where, every time you take a photo:

1. **Before the shutter** — the live viewfinder shows on-device composition aids (rule-of-thirds grid, horizon level, subject framing box, face-alignment hints) and, every ~2 seconds, posts a non-blocking AI suggestion ("background cluttered — try a lower angle", "subject too small — step closer").
2. **After the shutter** — the captured frame is automatically color-graded by a deterministic Core Image pipeline whose parameters are produced by a vision LLM that classifies the scene (portrait / food / landscape / night / interior / etc.) and prescribes scene-appropriate adjustments.

The LLM never produces pixels. It only emits structured JSON. All image operations run through Apple's Core Image so results are deterministic and re-runnable.

**Out of scope for v1 (this spec):** subscription / IAP, Sign in with Apple, App Store submission. The codebase will be structured so these can be added cleanly later.

## 2. User flow

```
[Open app] → [Camera permission gate] → [Camera view]
       │
       ▼
[Camera view shows live preview + on-device overlays @ 60 fps:
   - 3×3 rule-of-thirds grid (toggleable, default on)
   - horizon level (CMMotionManager pitch/roll)
   - subject saliency box (Vision framework)
   - face-alignment hints (Vision face detection)]
       │
       ▼ every ~2s, downsample to 1024px JPEG, POST to backend
[LLM Coach returns: {tip: string | null, priority: 'low'|'med'|'high'}]
       │
       ▼ overlay surfaces tip as bottom banner (fades after 4s)
       │
       ▼
[User taps shutter]
       │
       ▼
[Capture full-resolution photo (HEIC/JPEG via AVCapturePhotoOutput)]
       │
       ▼ downsample to 1024px JPEG, POST to backend
[LLM Colorist returns: SceneAnalysis + GradeParams JSON]
       │
       ▼
[Core Image pipeline applies GradeParams to full-resolution photo]
       │
       ▼
[Show before/after toggle for 3s, then save:
   - Graded JPEG → Camera Roll (PHPhotoLibrary)
   - Original + GradeParams JSON → app sandbox (for re-grade later)]
```

**Latency budget:**
- Coach round-trip: ≤ 1500 ms (1024px JPEG, fast vision model). If exceeded, drop the call and try again next tick.
- Colorist round-trip: ≤ 4000 ms (user is willing to wait briefly after shutter).
- Core Image grade application: ≤ 800 ms on iPhone 14+.

## 3. Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  iOS App (Swift 5.10 + SwiftUI + AVFoundation + Core Image)     │
│                                                                 │
│  ┌── CameraSession ────────────────────────────────────────┐   │
│  │  AVCaptureSession    AVCapturePhotoOutput              │    │
│  │  AVCaptureVideoDataOutput → preview frames @ 30 fps    │    │
│  └─┬──────────┬──────────────────────────┬──────────────────┘  │
│    │ preview  │ preview                   │ shutter photo      │
│    ▼ frame    ▼ frame                     ▼                    │
│  ┌─OnDeviceCV─┐  ┌─CoachThrottler─┐    ┌─SceneAnalyzer─┐       │
│  │ Vision FW: │  │ pick 1 frame   │    │ downsample to │       │
│  │  - face    │  │ every 2s,      │    │ 1024px JPEG,  │       │
│  │  - saliency│  │ downsample,    │    │ POST /grade   │       │
│  │ CoreMotion:│  │ POST /coach    │    │ → GradeParams │       │
│  │  - horizon │  └────┬───────────┘    └──────┬────────┘       │
│  └──┬─────────┘       │                       │                │
│     │ overlay state   │ coach tip             │ params         │
│     ▼                 ▼                       ▼                │
│  ┌─CameraView (SwiftUI)─────────┐    ┌─Grader (CIPipeline)─┐   │
│  │  preview + overlays + banner │    │ apply to full-res   │   │
│  └──────────────────────────────┘    │ → CIImage → CGImage │   │
│                                       │ → JPEG to Photos    │   │
│                                       └─────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                            │ HTTPS
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  Backend — Cloudflare Worker (TypeScript)                       │
│  POST /coach   { image_b64 } → { tip, priority }                │
│  POST /grade   { image_b64 } → { scene, grade }                 │
│  Per-IP token-bucket rate limit (KV).                           │
│  Calls Anthropic Claude API (claude-sonnet-4-6 + vision).       │
│  Hard-coded prompts versioned in source.                        │
└─────────────────────────────────────────────────────────────────┘
```

**Why this structure:**

- The two LLM calls (`/coach` and `/grade`) are separate because their prompts, schemas, latency budgets, and call cadences are all different. Forcing them through one endpoint would muddy both.
- The Worker is stateless; the only persistence is a small KV namespace for rate limiting. We deliberately avoid building auth/IAP infrastructure for v1.
- The on-device CV and the LLM Coach run in parallel. On-device CV drives the 60 fps overlays (horizon, grid, subject box). The LLM Coach drives an occasional, higher-level text banner. They never block each other.
- The original photo + `GradeParams` JSON is preserved in app sandbox so we can re-grade later without re-calling the LLM (free, instant retries with tweaks).

## 4. Color grading data model

The LLM emits a single `GradeParams` object. The Core Image pipeline applies these operations in a fixed order. All ranges are explicit so the LLM has zero ambiguity.

```typescript
type GradeParams = {
  // Tone (applied via CIToneCurve and CIExposureAdjust)
  exposure_ev: number;        // -2.0 … +2.0
  contrast: number;           // -50 … +50
  highlights: number;         // -100 … +100  (negative = recover)
  shadows: number;            // -100 … +100  (positive = lift)
  whites: number;             // -100 … +100
  blacks: number;             // -100 … +100

  // Color (CIColorControls / CIVibrance / CITemperatureAndTint)
  saturation: number;         // -100 … +100
  vibrance: number;           // -100 … +100
  temperature: number;        // -100 … +100  (negative = cooler)
  tint: number;               // -100 … +100  (negative = green, positive = magenta)

  // HSL adjustments per color band (CIColorMatrix-composed)
  hsl: {
    [band in 'red'|'orange'|'yellow'|'green'|'aqua'|'blue'|'purple'|'magenta']: {
      hue: number;            // -30 … +30  (degrees)
      saturation: number;     // -100 … +100
      luminance: number;      // -100 … +100
    }
  };

  // Finishing (CIVignetteEffect)
  vignette_intensity: number; // 0 … 1
  vignette_radius: number;    // 0.5 … 2.0
};

type SceneAnalysis = {
  scene: 'portrait' | 'group' | 'food' | 'landscape' | 'urban'
       | 'night' | 'interior' | 'product' | 'pet' | 'document' | 'other';
  lighting: 'harsh_sun' | 'golden_hour' | 'overcast' | 'shade' | 'indoor_warm'
          | 'indoor_cool' | 'mixed' | 'low_light' | 'flash';
  rationale: string;          // <=120 chars, shown in UI as "why this look"
};
```

**Why this exact schema:**

- Mirrors Lightroom's Basic + HSL panels, which is the canonical "what photographers want to adjust" surface. Any colorist (human or AI) thinks in these terms.
- Numeric ranges are concrete (no "high/medium/low"), so the LLM produces stable output and the pipeline is deterministic.
- `SceneAnalysis` is returned alongside so we can show the user *why* this look was chosen ("Indoor warm light, food close-up → boost vibrance, warm whites").

## 5. LLM contracts

### 5.1 Composition Coach

**Cadence:** at most once per 2 seconds, only when no in-flight coach call. Skip if last response was < 4s ago and unchanged.

**Input:** 1024px JPEG of current preview (quality 60%, ~50 KB).

**System prompt (versioned `coach-v1`):**

> You are a photographer's composition coach. You see a live viewfinder snapshot. Look for **one** issue that, if fixed, would meaningfully improve the photo. Return JSON only.
>
> Issues to consider, in order of priority:
> 1. Tilted horizon (advise rotation in degrees if visible).
> 2. Cluttered or distracting background.
> 3. Subject too small / too centered when off-center would be stronger.
> 4. Harsh lighting on subject (suggest moving relative to sun, or waiting).
> 5. Cut-off limbs or important objects.
>
> If the framing is already strong, return `{"tip": null, "priority": "low"}`.

**Output schema:**

```json
{ "tip": "step left so the lamp isn't growing out of his head", "priority": "med" }
```

`tip` must be ≤ 80 characters. `priority` ∈ {low, med, high}. UI shows `med` and `high` as banners; `low`/null is silent.

### 5.2 Colorist

**Cadence:** once per shutter press.

**Input:** 1024px JPEG of captured photo (quality 85%, ~200 KB).

**System prompt (versioned `colorist-v1`):**

> You are a senior colorist looking at a single photo. Your job:
> 1. Identify the scene type and lighting from the allowed enums.
> 2. Prescribe `GradeParams` to make the photo look its best **for that genre**.
>    - Portrait/Group: warm, soft skin tones, slight shadow lift, careful saturation on reds/oranges.
>    - Food: vibrant, warm, increased clarity, pull greens darker for contrast.
>    - Landscape: clear, punchy skies (pull blues), deeper greens, gentle dehaze (whites up, blacks down).
>    - Night: lift shadows but keep blacks crushed; reduce highlights; cool tint slightly to fight sodium-vapor cast.
>    - Interior: correct white balance, vibrance not saturation, lift shadows.
>    - …etc.
> 3. Conservative by default — most adjustments should be in ±30. Reserve large values for genuinely needed corrections.
> 4. Always include a 1-sentence `rationale` (≤120 chars).
>
> Return JSON conforming to the SceneAnalysis + GradeParams schema. No prose, no explanation outside JSON.

**Output:** `{ scene, lighting, rationale, grade: GradeParams }`.

The Worker validates against a Zod schema before returning to the app. Validation failure → return a neutral `GradeParams` (all zeros) so the app still displays *something*.

## 6. Core Image pipeline

Fixed order, regardless of `GradeParams` values:

```
CIImage from HEIC/JPEG
  → CIExposureAdjust              (exposure_ev)
  → CIHighlightShadowAdjust       (highlights, shadows)
  → CIToneCurve                   (whites/blacks → curve endpoints; contrast → S-curve)
  → CITemperatureAndTint          (temperature, tint)
  → CIColorControls               (saturation; brightness is no-op)
  → CIVibrance                    (vibrance)
  → 8 × CIHueAdjust + CIColorMatrix composites for HSL bands
  → CIVignetteEffect              (intensity, radius)
  → CIContext.createCGImage       → JPEG (quality 0.92)
```

**Performance:**
- All filters run on a `MTLDevice`-backed `CIContext` for GPU acceleration.
- One-shot operation per shutter; not real-time.
- iPhone 14: full 48 MP photo grades in ≈ 600–800 ms based on Apple's benchmarks for similar filter chains.

**Determinism:** given the same input image and `GradeParams`, the output bytes are deterministic (within Core Image's GPU-vs-CPU rounding; for snapshot tests we pin to CPU context).

## 7. On-device composition CV

| Aid | Source | Update rate |
|---|---|---|
| 3×3 rule-of-thirds grid | Static SwiftUI overlay | once |
| Horizon level (pitch + roll) | `CMMotionManager` | 60 Hz |
| Subject saliency box | `VNGenerateAttentionBasedSaliencyImageRequest` on preview frames | 10 Hz |
| Face detection box + tilt | `VNDetectFaceLandmarksRequest` | 10 Hz |

**Why these four and no others:** they cover 80% of beginner composition mistakes (tilted horizon, decentered subject, off-axis face). Additional aids (leading lines, golden ratio overlay) are explicit non-goals for v1 — they're noise on a small screen.

## 8. Backend

**Stack:** Cloudflare Worker (TypeScript), Hono framework, deployed via `wrangler`. Single worker, two routes.

**Secrets:** `ANTHROPIC_API_KEY` set via `wrangler secret put`. Never in source.

**Rate limiting:** Token bucket per source IP. 30 coach calls + 10 grade calls per hour per IP. Stored in Cloudflare KV. Exceeding → HTTP 429 with `Retry-After`. Bucket leakage rate is documented; on 429 the app shows a one-time banner and silently degrades coach to local-CV-only.

**No persistence of user images.** Image bytes are forwarded to Anthropic in the same request lifetime and never written to KV/R2/D1. Anthropic's API retention policy is documented in the app's Privacy section.

**Request shape:**

```http
POST /coach
Content-Type: application/json
{ "image_b64": "/9j/4AAQSkZ…" , "client_version": "1.0.0" }

POST /grade
Content-Type: application/json
{ "image_b64": "/9j/4AAQSkZ…" , "client_version": "1.0.0" }
```

**Response shape:** see §5.

## 9. Privacy

- All photos are taken locally. The original photo never leaves the device.
- The **1024px downsampled preview** (for coach) and **1024px downsampled capture** (for colorist) are sent to our backend, which forwards them to Anthropic and immediately discards the bytes.
- No user account, no telemetry tied to identity. The Worker logs only: timestamp, route, response code, byte count.
- App displays this on first launch in a privacy panel that the user must dismiss before camera access is requested.

## 10. Error handling

| Failure | Behavior |
|---|---|
| No network | Coach silently disables (local CV continues). Colorist after shutter falls back to a neutral preset (`auto white balance + slight shadows lift`). Banner: "调色服务离线,已使用默认参数。" |
| Coach timeout (>1.5s) | Drop that call. Try again next tick. No UI feedback. |
| Colorist timeout (>4s) | Cancel, fallback to neutral preset. Banner shown. |
| LLM returns invalid JSON | Backend validates with Zod; if fail, retry once with a stronger "JSON only" reminder. If still fail, return neutral preset. |
| Photo permission denied | Show explainer screen with "Open Settings" button. |
| Save to Photos fails | Keep graded image in app sandbox, surface a retry button. |
| Rate limit (429) | Coach disables for an hour; colorist falls back to neutral preset. |

## 11. Testing

- **Color pipeline (unit, Swift Testing):** golden-image tests. For 12 fixture photos (one per scene type), apply a fixed `GradeParams` and assert the SHA256 of the output matches a baseline. Catches Core Image regressions. CPU context only so cross-device deterministic.
- **GradeParams parsing (unit):** round-trip every range boundary; invalid JSON rejected; out-of-range clamped.
- **Worker (Vitest, miniflare):** mock Anthropic API; verify JSON validation; verify rate limit headers; verify 429 path.
- **Coach throttler (unit):** simulate frame stream; assert at most 1 in-flight call, ≥2s gap, dedup when tip unchanged.
- **Manual on-device:** shoot 30 photos across all 11 scene types; rate the grade and the coach hint subjectively. Track regressions in a spreadsheet.

## 12. Project structure

```
~/project/auteur/
├── app/                              # iOS app
│   ├── project.yml                   # xcodegen config
│   ├── Auteur/
│   │   ├── App/
│   │   │   ├── AuteurApp.swift       # @main
│   │   │   └── RootView.swift
│   │   ├── Camera/
│   │   │   ├── CameraSession.swift   # AVCaptureSession wrapper
│   │   │   ├── CameraView.swift      # SwiftUI view
│   │   │   └── CameraPreviewLayer.swift
│   │   ├── Compose/
│   │   │   ├── OnDeviceCV.swift      # Vision + CoreMotion
│   │   │   ├── CompositionOverlay.swift  # SwiftUI overlay
│   │   │   └── CoachThrottler.swift  # 2s cadence, in-flight guard
│   │   ├── Color/
│   │   │   ├── GradeParams.swift     # Codable struct
│   │   │   ├── CIPipeline.swift      # apply(params, to: CIImage)
│   │   │   └── NeutralPreset.swift
│   │   ├── LLM/
│   │   │   ├── BackendClient.swift   # /coach, /grade
│   │   │   └── ImageEncoder.swift    # resize + JPEG + base64
│   │   ├── Models/
│   │   │   ├── SceneAnalysis.swift
│   │   │   └── CoachTip.swift
│   │   ├── Views/
│   │   │   ├── BeforeAfterReveal.swift
│   │   │   └── PermissionGate.swift
│   │   └── Resources/
│   │       ├── Assets.xcassets
│   │       └── Info.plist
│   └── AuteurTests/
│       ├── GradeParamsTests.swift
│       ├── CIPipelineGoldenTests.swift
│       └── Fixtures/                 # 12 fixture jpegs + 12 baseline shas
├── backend/                          # Cloudflare Worker
│   ├── src/
│   │   ├── index.ts                  # Hono routes
│   │   ├── anthropic.ts              # API client
│   │   ├── schemas.ts                # Zod GradeParams + SceneAnalysis
│   │   ├── prompts.ts                # versioned system prompts
│   │   └── ratelimit.ts              # KV token bucket
│   ├── test/
│   │   └── index.test.ts             # vitest + miniflare
│   ├── wrangler.toml
│   ├── package.json
│   └── tsconfig.json
└── docs/
    └── superpowers/
        ├── specs/2026-05-13-auteur-design.md  ← this file
        └── plans/                              ← generated next
```

## 13. Non-goals for v1

- Manual editing sliders after the auto-grade. (Tap to re-roll with same params is the only post-edit.)
- Subscription, IAP, Sign in with Apple. Wired-in stubs only, no real surface.
- Style presets / film emulation. Scene-adaptive is the entire pitch.
- iPad layouts, Mac Catalyst, Apple Watch. iPhone portrait only.
- Sharing UI (Save to Photos is enough — users share from there).
- Multi-photo / burst / live-photo / video.

## 13a. Addendum (2026-05-14) — Pose guidance

Two layers, both AI-driven, both consume the **existing** `/api/coach` endpoint — no new
dependency, no new API surface, no new UI chrome.

### 13a.1 Body-pose monitoring (passive feedback)

Real-time skeleton from `VNDetectHumanBodyPoseRequest` (10 Hz). Local code derives
shoulder slant / spine tilt / head tilt; the worst issue surfaces as a small banner.

| Aid | Source | Update rate |
|---|---|---|
| Body skeleton + joint dots | `VNDetectHumanBodyPoseRequest` | 10 Hz |
| Local pose hints (shoulder slant, spine tilt, head tilt) | derived from joints | 10 Hz |

### 13a.2 AI-placed pose silhouette (active guidance, the "magic")

The Coach LLM now returns up to four optional fields per call:

```ts
pose_id:     'stand' | 'arms_open' | 'walk' | 'wave' | 'yoga' |
             'mind_body' | 'dance' | 'child_lift' | null
pose_x:      number   // 0..1 horizontal CENTER position on viewfinder
pose_y:      number   // 0..1 vertical CENTER position on viewfinder
pose_height: number   // 0.3..0.95 silhouette height as fraction of viewfinder height
```

When set, the iOS app renders the corresponding silhouette (SF Symbols `figure.*`) at
the prescribed screen-space coordinates with a white neon-outline glow at 55 % opacity.

**The composition trick:** the silhouette is **screen-fixed**, not world-anchored. As the
user moves the phone, the outline stays where it is on screen; the user must walk /
tilt / pan so the real subject in the world fills the outline. Once they do, the subject
is automatically (a) in a flattering pose and (b) in a well-composed position (rule of
thirds / headroom / negative space chosen by the model from scene context).

**Library:** 8 built-in poses backed by SF Symbols — zero asset weight, vector at any size.
Future versions can replace SF Symbols with on-device person-segmentation
(`VNGeneratePersonSegmentationRequest`) of user-imported reference photos.

**Non-interactive by design:** no picker, no manual placement, no opacity slider, no
drag/pinch. The model owns selection + placement + size; the user just shoots.

**Prompt:** Coach bumped to `coach-v3`. Old `v1/v2` constants are kept as aliases for
back-compat during deploy.

## 14. Open decisions deferred to later specs

- **Subscription model and free-tier cap.** Will be its own spec once we have TestFlight feedback on retention.
- **Sign in with Apple.** Required if any other login exists; we have none, so deferred.
- **Backend persistence of `GradeParams` for cross-device history.** Currently sandbox-only.
- **Localizations.** v1 is zh-Hans + en only, strings keyed for later expansion.

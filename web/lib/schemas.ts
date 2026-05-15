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
  // 200 — Gemini sometimes writes 130-150 char rationales even when prompted for "<=120 chars".
  // Cheap to widen here; UI truncates for display anyway.
  rationale: z.string().max(200),
  grade:     GradeParamsSchema,
  // Set true only when the LLM service genuinely failed (exception / misconfig),
  // so the client can distinguish a real failure from a real "neutral" grade.
  degraded:  z.boolean().optional(),
})

export type SceneAnalysis = z.infer<typeof SceneAnalysisSchema>

/** Must mirror PoseLibrary.templates in the iOS app. */
export const POSE_IDS = [
  'stand', 'arms_open', 'walk', 'wave', 'yoga', 'mind_body', 'dance', 'child_lift',
] as const

/**
 * AI guidance — on-demand, one-shot. Returned by /api/guidance.
 *
 * Two modes by subject:
 *   - person   : show pose silhouette at (pose_x, pose_y), height pose_height
 *   - scene    : show target framing box (target_x/y/w/h)
 *   - empty    : no main subject — UI hides overlay
 *
 * Always: suggested_zoom in [1, 3]. iOS applies this to AVCaptureDevice.videoZoomFactor
 * immediately when the guidance appears, then the user moves the phone until the live
 * subject overlaps the target. On-device IoU monitor triggers auto-shutter once aligned.
 *
 * No text fields — all guidance is visual, driven by UI overlays.
 */
export const AIGuidanceSchema = z.object({
  subject_type: z.enum(['person', 'scene', 'empty']),

  // Person mode
  pose_id:     z.enum(POSE_IDS).nullable().optional(),
  pose_x:      z.number().min(0).max(1).optional(),
  pose_y:      z.number().min(0).max(1).optional(),
  pose_height: z.number().min(0.3).max(0.95).optional(),

  // Scene mode — target bounding box for the main subject
  target_x: z.number().min(0).max(1).optional(),
  target_y: z.number().min(0).max(1).optional(),
  target_w: z.number().min(0.1).max(1).optional(),
  target_h: z.number().min(0.1).max(1).optional(),

  // Always — capped to common iPhone wide-cam range
  suggested_zoom: z.number().min(1).max(3).default(1),

  // Set true only when the LLM service genuinely failed (exception / misconfig),
  // so the client can distinguish a real failure from a real "no subject" result.
  degraded: z.boolean().optional(),
})

export type AIGuidance = z.infer<typeof AIGuidanceSchema>

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

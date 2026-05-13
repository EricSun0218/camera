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

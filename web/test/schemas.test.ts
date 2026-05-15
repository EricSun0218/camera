import { describe, it, expect } from 'vitest'
import { GradeParamsSchema, SceneAnalysisSchema, CoachTipSchema, neutralGrade } from '../lib/schemas'

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

  it('rejects rationale > 200', () => {
    expect(() => SceneAnalysisSchema.parse({
      scene: 'portrait', lighting: 'harsh_sun', rationale: 'x'.repeat(201), grade: neutralGrade(),
    })).toThrow()
  })

  it('accepts rationale up to 200 (Gemini can hit ~150)', () => {
    expect(() => SceneAnalysisSchema.parse({
      scene: 'portrait', lighting: 'harsh_sun', rationale: 'x'.repeat(180), grade: neutralGrade(),
    })).not.toThrow()
  })

  it('accepts a complete valid payload', () => {
    const ok = SceneAnalysisSchema.parse({
      scene: 'portrait', lighting: 'golden_hour', rationale: 'warm soft skin', grade: neutralGrade(),
    })
    expect(ok.scene).toBe('portrait')
  })
})

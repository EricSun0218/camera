import { describe, it, expect } from 'vitest'
import {
  GradeParamsSchema, SceneAnalysisSchema,
  AIGuidanceSchema, POSE_IDS,
  neutralGrade,
} from '../lib/schemas'

describe('AIGuidanceSchema', () => {
  it('accepts empty subject', () => {
    expect(AIGuidanceSchema.parse({ subject_type: 'empty', suggested_zoom: 1 }))
      .toEqual({ subject_type: 'empty', suggested_zoom: 1 })
  })

  it('accepts person mode with pose placement', () => {
    const r = AIGuidanceSchema.parse({
      subject_type: 'person',
      pose_id: 'stand', pose_x: 0.67, pose_y: 0.55, pose_height: 0.72,
      suggested_zoom: 1.5,
    })
    expect(r.pose_id).toBe('stand')
  })

  it('accepts scene mode with target box', () => {
    const r = AIGuidanceSchema.parse({
      subject_type: 'scene',
      target_x: 0.5, target_y: 0.55, target_w: 0.7, target_h: 0.5,
      suggested_zoom: 1.8,
    })
    expect(r.target_w).toBe(0.7)
  })

  it('rejects invalid subject_type', () => {
    expect(() => AIGuidanceSchema.parse({ subject_type: 'underwater', suggested_zoom: 1 })).toThrow()
  })

  it('rejects suggested_zoom out of range', () => {
    expect(() => AIGuidanceSchema.parse({ subject_type: 'empty', suggested_zoom: 5 })).toThrow()
  })

  it('rejects unknown pose_id', () => {
    expect(() => AIGuidanceSchema.parse({
      subject_type: 'person', pose_id: 'flying', pose_x: 0.5, pose_y: 0.5, pose_height: 0.5, suggested_zoom: 1,
    })).toThrow()
  })

  it('defaults suggested_zoom to 1 if missing', () => {
    const r = AIGuidanceSchema.parse({ subject_type: 'empty' })
    expect(r.suggested_zoom).toBe(1)
  })

  it('pose_id can be null (person frame OK as-is, no overlay needed)', () => {
    const r = AIGuidanceSchema.parse({ subject_type: 'person', pose_id: null, suggested_zoom: 1 })
    expect(r.pose_id).toBeNull()
  })

  it('POSE_IDS export is the canonical list iOS depends on', () => {
    expect(POSE_IDS).toContain('stand')
    expect(POSE_IDS).toContain('arms_open')
    expect(POSE_IDS.length).toBe(8)
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

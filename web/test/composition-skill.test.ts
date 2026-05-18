import { describe, it, expect } from 'vitest'
import { COMPOSITION_SKILL, COMPOSITION_SKILL_VERSION } from '@/lib/composition-skill'
import { POSE_IDS } from '@/lib/schemas'

describe('composition skill', () => {
  it('has a version', () => {
    expect(COMPOSITION_SKILL_VERSION).toBe('composition-skill-v1')
  })

  it('preserves the load-bearing output-format anchors', () => {
    // /api/guidance parses model output against AIGuidanceSchema — the skill
    // must keep instructing the exact JSON shape or guidance silently degrades.
    for (const key of ['subject_type', 'pose_id', 'pose_x', 'pose_y', 'pose_height',
                        'target_x', 'target_y', 'target_w', 'target_h', 'suggested_zoom']) {
      expect(COMPOSITION_SKILL).toContain(key)
    }
    expect(COMPOSITION_SKILL).toContain('Strict JSON')
  })

  it('lists every pose_id the schema accepts', () => {
    for (const id of POSE_IDS) {
      expect(COMPOSITION_SKILL).toContain(`"${id}"`)
    }
  })

  it('keeps the three subject types', () => {
    for (const t of ['person', 'scene', 'empty']) {
      expect(COMPOSITION_SKILL).toContain(`"${t}"`)
    }
  })
})

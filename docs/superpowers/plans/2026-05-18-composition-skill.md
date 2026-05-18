# Composition Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the thin `GUIDANCE_SYSTEM_PROMPT_V4` with a structured composition-expert knowledge module (`composition-skill.ts`) that mirrors the existing `colorist-skill.ts` pattern.

**Architecture:** A new `web/lib/composition-skill.ts` exports the full system prompt for `/api/guidance`. The `AIGuidance` output schema is unchanged — only the reasoning quality improves. `web/lib/prompts.ts` (which held only the old prompt) is deleted; the guidance route imports the new module.

**Tech Stack:** TypeScript, Next.js (App Router) API routes, Vitest. Web app at `web/`.

**Conventions:**
- All work commits directly to `main` (no feature branch).
- Every commit message ends with the `Co-Authored-By` footer shown in the commit steps.
- All commands run from the `web/` directory.

**Spec:** `docs/superpowers/specs/2026-05-18-composition-skill-design.md`

---

### Task 1: Composition skill module + structural test (TDD)

The skill is a prose knowledge module; its *prose* can't be unit-tested, but the **load-bearing mechanical anchors** (output-format keys, every `pose_id` the schema accepts) can — drift there silently degrades guidance. Test those.

**Files:**
- Create: `web/test/composition-skill.test.ts`
- Create: `web/lib/composition-skill.ts`

- [ ] **Step 1: Write the failing test**

Create `web/test/composition-skill.test.ts`:

```typescript
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
      expect(COMPOSITION_SKILL).toContain(t)
    }
  })
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd web && npx vitest run test/composition-skill.test.ts`
Expected: FAIL — cannot resolve `@/lib/composition-skill` (module does not exist yet).

- [ ] **Step 3: Create the composition skill module**

Create `web/lib/composition-skill.ts` with exactly this content:

```typescript
/**
 * Composition Skill — Cue's framing & composition expert module.
 *
 * This is the knowledge the LLM is given every time the app gives composition
 * guidance (invoked by /api/guidance). It encodes professional photographic
 * composition practice: a philosophy, a reasoning workflow, the composition
 * principles, subject-placement rules, and per-shot-type recipes.
 *
 * The model only ever outputs AIGuidance JSON — a subject placement, a size,
 * and a zoom. The iOS app renders that as an alignment overlay; the user pans
 * the phone to match it and the app auto-zooms to the target size.
 *
 * To evolve the composer, edit THIS file. /api/guidance picks it up automatically.
 */

export const COMPOSITION_SKILL_VERSION = 'composition-skill-v1'

export const COMPOSITION_SKILL = `You are Cue's composer — a master photographer's eye. You see ONE viewfinder snapshot and decide how the shot should be framed. You output only numbers: where the subject belongs, how large it should be, and a zoom. A deterministic UI overlay renders your decision; the user pans the phone to match it.

═══ PHILOSOPHY (never violate) ═══
1. ONE SUBJECT, ONE STORY. Find the single clearest subject. Every composition choice serves it. If the frame holds many things, pick the one with the most visual interest and commit.
2. PLACEMENT IS INTENT. Never center a subject by default — a centered subject is static and reads as a snapshot. Place it on a rule-of-thirds line or intersection. Center ONLY when symmetry is the deliberate point (reflections, formal architecture, a head-on portrait stare).
3. ROOM TO BREATHE. A subject that faces or moves in a direction needs open space ahead of it (look-room). A head needs correct headroom. A subject crammed against an edge looks like it is leaving the frame.
4. FILL WITH PURPOSE. The subject should command the frame. Empty space is good ONLY when it is deliberate, calm negative space — never accidental dead space from a subject that is too small or too far.
5. EXPRESSIBLE GUIDANCE ONLY. See the next section — reason only about what you can actually output.

═══ WHAT YOU CAN AND CANNOT CONTROL ═══
Your guidance reaches the user as exactly three things: the subject's PLACEMENT (screen position), the subject's SIZE in the frame, and a ZOOM. The user obeys it by PANNING the phone; the app then AUTO-ZOOMS so the subject matches the size you asked for.
- You CAN control: where the subject sits in the frame, how much of the frame it fills, and zoom.
- You CANNOT control: camera height, tilt, lens angle, or asking the user to walk around. Do NOT reason about "shoot from a low angle", "get down to eye level", or "change your perspective" — you cannot express it, so it is wasted reasoning.
- The SIZE you choose (target_w / target_h, or pose_height) directly drives the auto-zoom. It IS the framing — decide it deliberately, never as an afterthought.
- Place the subject where a pan can plausibly bring it — guidance is a nudge, not a teleport.

═══ WORKFLOW — reason in this order ═══
A. READ THE FRAME. Name what is in it. Lock onto the ONE subject.
B. CLASSIFY THE SHOT (internally — you do not output this): portrait, group, full-body, candid, landscape, architecture, food, product, pet, interior, other.
C. CHOOSE THE COMPOSITION. Pick the principle(s) that fit this shot and subject. Decide the subject's ideal screen position and its ideal size in the frame.
D. SET THE TARGET. Translate the decision into the output numbers.

═══ COMPOSITION PRINCIPLES ═══
- RULE OF THIRDS — the default. Place the subject (for a person, their core/eyes) on a third line or intersection (x ≈ 0.33 or 0.67). Use for almost everything. Skip only for deliberate symmetry.
- LEADING LINES — when roads, rails, edges, or shadows run through the frame, place the subject where those lines point so the eye is carried to it.
- FRAMING — when foreground elements (arches, doorways, branches) surround the subject, keep the subject the clear focus inside that frame, not crowded by it.
- BALANCE / VISUAL WEIGHT — an off-center subject leaves one side lighter. Fine if a smaller secondary element fills it; otherwise pull the subject slightly back toward center so the frame is not lopsided.
- NEGATIVE SPACE — a small subject in a large calm empty area is powerful AND deliberate. Use for minimalist scenes; the empty area must be quiet (sky, wall, water), not clutter.
- FILL THE FRAME — for detail, texture, food, product, tight portraits: let the subject occupy most of the frame.
- SYMMETRY — reflections, corridors, formal facades, head-on stares: center the subject and balance both halves.
- DEPTH / LAYERING — for scenes, prefer a framing that keeps a foreground anchor low in the frame so the image has near/far depth, not one flat plane.
- SIMPLIFY — favor the cleaner framing. When two placements are close, pick the one with the less cluttered surroundings.
- RULE OF ODDS — for clusters of small objects, an odd count (3, 5) is more engaging; frame to include an odd group when you can.
- FIGURE-TO-GROUND — choose a placement where the subject stands clear of its background, not merged into it.
- DIAGONALS & TRIANGLES — for dynamic scenes and multi-element groups, a placement along a diagonal adds energy; a calm scene wants the subject squarer to the grid.

═══ PLACEMENT RULES ═══
- HEADROOM: leave a little space above a head, not a lot. A big gap above the head sinks the subject. Cropping the top of the head is acceptable ONLY in a deliberately tight portrait.
- EYES: for a head-and-shoulders person, the eyes belong about 1/3 of the way down from the top. This sets correct headroom automatically.
- LOOK-ROOM: if the subject faces or moves LEFT, place it on the RIGHT third (open space ahead of it), and vice versa. Never trap a facing subject against the edge it faces.
- HORIZON: never place a horizon dead-center. Put it on the lower third to feature the sky, the upper third to feature the ground/foreground.
- DANGER ZONES: do not frame so the subject is cut at a joint (wrist, elbow, knee, ankle, waist) — crop between joints. Avoid a placement where a background line or pole appears to grow out of the subject.

═══ SUBJECT TYPE — pick exactly one ═══
You MUST return actionable guidance — "person" or "scene" — for essentially every frame. A camera pointed at anything has a scene.
- "person" — at least one person is visible, even partially. Return a pose silhouette + screen placement.
- "scene"  — the default for everything else. ANY frame with discernible content — a room, a desk, a plant, food, a wall, a street, an object, an animal, even a plain or cluttered or boring view — is a "scene". Pick the most interesting element (or the natural focal area) and return a target box for it. When in doubt, this is the answer.
- "empty"  — almost never. ONLY when the frame carries NO information at all: the lens is physically covered, the frame is pure black, or motion blur is so total that nothing whatsoever is recognizable. A plain, dim, or uninteresting frame is NOT empty — it is a "scene". If you can name anything you see, it is a "scene".
Bias hard toward "scene" over "empty". If you are even slightly unsure, return "scene" with your best-guess target box.

═══ PERSON MODE — also return ═══
  pose_id     : one of "stand", "arms_open", "walk", "wave", "yoga", "mind_body", "dance", "child_lift" — the closest flattering pose for this person and scene.
  pose_x      : 0..1, horizontal screen center of the silhouette. Prefer 0.33 or 0.67 over 0.5. If the person faces a side, give look-room: facing left → pose_x ≈ 0.67.
  pose_y      : 0..1, vertical screen center. ~0.50–0.60 for full-body, ~0.50–0.55 for a portrait (keeps headroom, lands the eyes near the upper third).
  pose_height : 0.3..0.95, silhouette height as a fraction of viewfinder height. THIS drives the framing — full-body ≈ 0.80–0.92; three-quarter ≈ 0.70–0.82; head-and-shoulders portrait ≈ 0.55–0.70.

═══ SCENE MODE — also return ═══
  target_x : 0..1, horizontal center of the subject box. Prefer a third (0.33 / 0.67) unless symmetry calls for 0.5.
  target_y : 0..1, vertical center.
  target_w : 0.1..1, box width as a fraction of viewfinder width.
  target_h : 0.1..1, box height as a fraction of viewfinder height.
  The box SIZE is the framing — size it to the ideal crop; it drives the auto-zoom.

═══ SHOT-TYPE RECIPES (concrete starting points — adapt to the actual frame) ═══
- portrait (one person): head-and-shoulders, pose_height ≈ 0.55–0.70; pose_y ≈ 0.50–0.55 (eyes near the upper third); pose_x on a third; look-room toward the gaze direction.
- group: people fill the frame width, pose_height ≈ 0.70–0.88; minimal dead space above heads; pose_x near 0.5 is acceptable for a balanced row, otherwise a third.
- full-body: pose_height ≈ 0.80–0.92; pose_y ≈ 0.52–0.60; more space below the feet than above the head; never crop at ankles or knees.
- candid: subject medium-sized inside its environment; pose/target on a third intersection; strong look-room ahead of motion or gaze.
- landscape: the scene is the subject; wide box, target_w ≈ 0.85–1.0; horizon implied on a third (target_y ≈ 0.62–0.70 to feature sky); keep a foreground anchor.
- architecture: building fills the frame; vertical emphasis (target_h > target_w) for height; center it if symmetric, otherwise use its leading lines.
- food: tight, appetizing crop, target_w/h ≈ 0.70–0.88; slightly off-center; leave one calm side of negative space.
- product / still life: clean, fairly tight, target_w/h ≈ 0.65–0.85; centered for a hero shot, on a third for lifestyle context; the subject must stand clear of the background.
- pet / animal: like a portrait; box or silhouette tighter for personality; eyes on the upper third; look-room toward the gaze.
- interior: show the room with depth, target_w ≈ 0.85–1.0; place the box so the eye has a path into the room, not blocked by near furniture.
- other: lean on the philosophy — one subject, off-center, filling the frame with purpose.

═══ ZOOM ═══
suggested_zoom in [1.0, 3.0] — a coarse hint only; the app computes precise zoom from your target size. Subject small in the frame → zoom > 1.0; subject already well-sized, or a wide environmental shot → 1.0.

═══ TASK ═══
1. Read the frame; lock onto the one subject.
2. Classify the shot type internally.
3. Choose the composition and matching recipe; decide the subject's position AND size.
4. Output strict JSON only.

If subject_type = "empty", omit all other fields.

OUTPUT FORMAT: Strict JSON, NO prose, NO markdown fences:
{
  "subject_type": "person" | "scene" | "empty",
  "pose_id":        "<enum>" | null,        // person only
  "pose_x":         <0..1>,                  // person only
  "pose_y":         <0..1>,                  // person only
  "pose_height":    <0.3..0.95>,             // person only
  "target_x":       <0..1>,                  // scene only
  "target_y":       <0..1>,                  // scene only
  "target_w":       <0.1..1>,                // scene only
  "target_h":       <0.1..1>,                // scene only
  "suggested_zoom": <1..3>
}\`
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd web && npx vitest run test/composition-skill.test.ts`
Expected: PASS — all 4 tests green.

- [ ] **Step 5: Commit**

```bash
git add web/lib/composition-skill.ts web/test/composition-skill.test.ts
git commit -m "$(cat <<'EOF'
feat(web): composition skill — structured framing/composition expert module

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Wire the route and remove the old prompt

**Files:**
- Modify: `web/app/api/guidance/route.ts`
- Delete: `web/lib/prompts.ts`

- [ ] **Step 1: Repoint the guidance route import**

In `web/app/api/guidance/route.ts`, find:

```typescript
import { GUIDANCE_SYSTEM_PROMPT_V4 } from '@/lib/prompts'
```

Replace with:

```typescript
import { COMPOSITION_SKILL } from '@/lib/composition-skill'
```

- [ ] **Step 2: Use the new skill as the system prompt**

In the same file, find:

```typescript
        system: GUIDANCE_SYSTEM_PROMPT_V4,
```

Replace with:

```typescript
        system: COMPOSITION_SKILL,
```

- [ ] **Step 3: Delete the obsolete prompts module**

```bash
git rm web/lib/prompts.ts
```

`GUIDANCE_SYSTEM_PROMPT_V4` had only two references — its definition in `prompts.ts` and the import just rewritten — so nothing else dangles.

- [ ] **Step 4: Verify the build type-checks**

Run: `cd web && npm run build`
Expected: build succeeds with no TypeScript errors (a dangling `@/lib/prompts` import would fail here).

- [ ] **Step 5: Run the full test suite**

Run: `cd web && npm test`
Expected: all tests pass — `schemas`, `routes`, `llm`, and `composition-skill`. `routes.test.ts` mocks `@/lib/llm`, so swapping the system prompt does not change its behavior; it must stay green.

- [ ] **Step 6: Commit**

```bash
git add web/app/api/guidance/route.ts web/lib/prompts.ts
git commit -m "$(cat <<'EOF'
feat(web): guidance route uses the composition skill; drop prompts.ts

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Manual verification (post-implementation, needs LLM credentials)

Not automatable in this plan — the route's `/api/llm` config needs real API credentials and a sample image. After implementation, with the dev server running and env configured, POST a real viewfinder JPEG (base64) to `/api/guidance` and confirm the response is a well-formed `AIGuidance` JSON (valid `subject_type`, populated `pose_*`/`target_*`, `suggested_zoom` in range). This guards against the prompt rewrite skewing the output format — the route has a fallback so it will not crash, but guidance quality would silently degrade.

---

## Self-Review

**Spec coverage:**
- §2 new `composition-skill.ts` with `COMPOSITION_SKILL` + `COMPOSITION_SKILL_VERSION` → Task 1. ✓
- §2 delete `prompts.ts`, repoint route import + `system:` → Task 2. ✓
- §3 skill content structure (philosophy, workflow, principles, placement rules, subject type, person/scene modes, shot-type recipes, task, output format) → Task 1 Step 3 full content. ✓
- §4 Cue-specific constraints (placement+size+zoom only; no camera-height reasoning; size drives auto-zoom; pannable placement; `suggested_zoom` as coarse hint) → "WHAT YOU CAN AND CANNOT CONTROL" + "ZOOM" sections. ✓
- §5 preserved mechanics (person/scene/empty bias, 8 `pose_id` enums, field ranges, JSON output) → "SUBJECT TYPE", "PERSON MODE", "SCENE MODE", "OUTPUT FORMAT" sections, plus Task 1 test asserts the anchors. ✓
- §6 verification (build, no dangling refs, string assertions, eval call) → Task 1 test + Task 2 Steps 4–5 + Manual verification section. ✓
- §7 file list → Tasks 1 & 2 file headers. ✓

**Placeholder scan:** No TBD/TODO. Task 1 Step 3 contains the complete module content; every command has an expected result.

**Type consistency:** `COMPOSITION_SKILL` / `COMPOSITION_SKILL_VERSION` are the exported names used identically in the test (Task 1 Step 1), the module (Task 1 Step 3), and the route (Task 2 Steps 1–2). `POSE_IDS` is imported from the existing `@/lib/schemas`. The skill's `pose_id` enum values match `POSE_IDS` exactly (`stand, arms_open, walk, wave, yoga, mind_body, dance, child_lift`).

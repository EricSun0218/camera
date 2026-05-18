# Design System — Cue

## Product Context
- **What this is:** an iOS 26 camera app. Tap "AI guidance" → the app frames the shot for you (two-ball alignment → auto-shutter) → photos land in an in-app library → optional one-tap AI color grading.
- **Who it's for:** people who want better photos without learning photography. The person holding the phone is often not the person being photographed.
- **Space/industry:** consumer camera / photo apps. Peers: Apple Camera, Apple Photos, Halide, VSCO, 醒图.
- **Project type:** native iOS app (SwiftUI, iOS 26).

## The Memorable Thing
The moment the alignment ball snaps green and the shutter fires on its own. "The camera framed the shot for me." Every design decision serves that moment: the UI must get out of the way so the viewfinder — and the photo — is the whole experience.

## Aesthetic Direction
- **Direction:** Invisible UI / content-first. The photo is the hero; chrome is a thin glass layer that floats and never competes.
- **Decoration level:** minimal. No texture, no ornament. The only "decoration" is Liquid Glass refraction and one accent color.
- **Mood:** calm, precise, quietly high-tech. Confident, not loud. It should feel like a tool Apple could have shipped.
- **Reference feel:** Apple Camera + Apple Photos (content-first black canvas, floating controls), Halide (precision instrument).

## Surfaces & Color
Pure black is the canvas — photos and the viewfinder pop hardest against true black, and it matches the iOS 26 Photos app.

- **Canvas:** `#000000` — camera viewfinder background, library background, editor background.
- **Chrome:** Liquid Glass (`.glassEffect(.regular, …)`) — never a solid fill. Controls are glass capsules / circles that float over content.
- **Primary text:** `#FFFFFF`.
- **Secondary text:** white at 55–65% opacity. Tertiary: white at 30–40%.
- **Accent — Cue Cyan:** `#3DD6E6` (a clean, slightly-cool cyan). Used ONLY for: the AI action, the "aligned / go" state, the current selection. Accent is rare and always means "AI" or "active". Never decorative.
- **Alignment state colors:** white (not aligned) → `#F5C518` amber (close) → `#34E27A` green (locked). These are functional signal colors, not brand colors.
- **Semantic:** error `#FF5A52`, success = the same green. Shown as tinted glass capsules, never solid banners.
- **No gradients** except the one existing cyan→blue on the AI button core (it reads as an energy source — keep it, do not add others).

## Typography
Native iOS. **Use SF Pro (the system font) — `Font.system`.** On iOS, fighting the system font looks worse, not better; SF Pro is the correct, premium choice for a native app. (Web font blacklists do not apply here.)

- **Display / large titles:** `.system(size: 28–34, weight: .bold)` — used sparingly (empty states, big moments).
- **Titles / nav:** `.system(size: 17, weight: .semibold)`.
- **Body / labels:** `.system(size: 15, weight: .regular/.medium)`.
- **Captions / metadata:** `.system(size: 12–13, weight: .medium)`.
- **Numerals in any data context:** `.monospacedDigit()`.
- Cue has very little text — it's a camera. Every string earns its place. No marketing copy, no chatty captions. Guidance is visual (balls, arrows), never paragraphs.

## Spacing
- **Base unit:** 4pt. Scale: 4 / 8 / 12 / 16 / 24 / 32 / 48.
- **Density:** comfortable. Generous tap targets (≥44pt). Photo grids are the one exception — dense, near-gapless, like Apple Photos.
- **Screen-edge inset for floating chrome:** 14–16pt.

## Layout
- **Camera:** full-bleed viewfinder. One floating control row at the bottom (gallery · shutter · AI). Status as a glass capsule near the top. Nothing else.
- **Library:** full-bleed black. Dense 3-column square grid, 2pt gaps (Apple Photos Library tab). Floating glass nav on top, grid scrolls under it.
- **Photo detail:** the photo fills the screen. A horizontal filmstrip of the whole library sits at the bottom (swipe to move between photos, Apple Photos style). A floating glass action cluster below that.
- **Corner radii:** concentric. Grid cells ~4pt. Glass capsules use `.capsule`. Cards/sheets 16–22pt. Circular controls are true circles.

## Liquid Glass Rules (iOS 26)
- Glass is the navigation/control layer ONLY. Never on a photo, never on content.
- Never stack glass on glass. Group sibling glass elements in a `GlassEffectContainer`.
- Apply `.glassEffect()` last in the modifier chain.
- Tint only the primary action (the AI button) with Cue Cyan. Everything else is untinted regular glass.
- The shutter button stays the classic white camera ring — a known affordance, not glassed.

## Motion
- **Approach:** intentional and physical. Motion explains state; it is never decoration.
- **Signature moments:** the AI button's idle pulse + ripple (invites the tap); the loading overlay's concentric rings + scan line; the alignment ball gliding and the target ball pulsing green when locked; glass morphing between states.
- **Easing:** `.easeInOut` for state, `.easeOut` for entrances, spring (`response: 0.3, dampingFraction: 0.85`) for things the user triggers.
- **Duration:** micro 120ms, standard 250–350ms. Auto-shutter alignment hold is 0.3s.

## Decisions Log
| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-05-18 | Initial design system | Established by /design-consultation. Direction: invisible content-first UI, pure-black canvas, Liquid Glass chrome, single cyan accent. Serves the memorable moment: the camera framing the shot for you. |

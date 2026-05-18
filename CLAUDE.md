# Cue

iOS 26 camera app: AI composition guidance + manual AI color grading.
iOS app in `app/` (SwiftUI, xcodegen). Backend in `web/` (Next.js on Vercel).

## Design System
Always read DESIGN.md before making any visual or UI decision.
Font choices, colors, spacing, and aesthetic direction are defined there.
Do not deviate without explicit user approval.

## Build
- iOS: `cd app && xcodegen generate` then build `Cue.xcodeproj` (target iOS 26).
- Backend: `cd web && npm test && npx next build`.

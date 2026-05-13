# Auteur

iOS camera app: AI scene-adaptive auto color grading + real-time composition guidance.

LLM analyzes; deterministic Core Image renders.

## Setup

### Requirements
- macOS 14+ with Xcode 16+ installed (App Store)
- An Anthropic API key
- A Vercel account linked to this GitHub repo

### iOS app
1. `cd app && xcodegen generate`
2. Open `Auteur.xcodeproj` in Xcode
3. Set your development team in target signing
4. Edit `app/Auteur/LLM/BackendClient.swift` — set `BackendClient.baseURL` to your deployed Vercel URL
5. Build + run on an iPhone (camera does not work in simulator)

### Backend (Vercel / Next.js)
1. Push to GitHub triggers Vercel auto-deploy (via Vercel GitHub integration)
2. In Vercel project settings, set env var: `ANTHROPIC_API_KEY` (production + preview)
3. Production URL → paste into `app/Auteur/LLM/BackendClient.swift`: `BackendClient.baseURL`
4. Routes: `POST /api/coach`, `POST /api/grade`, `GET /api/health`

Local dev: `cd web && npm run dev` (default port 3000)
Tests: `cd web && npm test`

### Tests
- Backend: `cd web && npm test`
- iOS: open in Xcode, ⌘U

## Architecture
See `docs/superpowers/specs/2026-05-13-auteur-design.md`.

# Auteur

iOS camera app: AI scene-adaptive auto color grading + real-time composition guidance.

LLM analyzes; deterministic Core Image renders.

## Setup

### Requirements
- macOS 14+ with Xcode 16+ installed (App Store)
- An Anthropic API key
- A Cloudflare account + `wrangler` CLI (`npm i -g wrangler`)

### iOS app
1. `cd app && xcodegen generate`
2. Open `Auteur.xcodeproj` in Xcode
3. Set your development team in target signing
4. Edit `app/Auteur/LLM/BackendClient.swift` — set `BackendClient.baseURL` to your deployed Worker URL
5. Build + run on an iPhone (camera does not work in simulator)

### Backend (Cloudflare Worker)
1. `cd backend && npm install`
2. `npx wrangler secret put ANTHROPIC_API_KEY`
3. `npx wrangler kv namespace create RATELIMIT` — paste returned `id` into `wrangler.toml`
4. `npx wrangler deploy`
5. Note the deployed URL; paste it into `BackendClient.baseURL` (step 4 above)

### Tests
- Backend: `cd backend && npm test`
- iOS: open in Xcode, ⌘U

## Architecture
See `docs/superpowers/specs/2026-05-13-auteur-design.md`.

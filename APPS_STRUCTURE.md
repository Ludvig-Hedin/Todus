# Todus Apps Structure

**Last Updated**: 2026-03-01

## Active Apps (Only These Are Supported)

### 1. `apps/ios` — iPhone Native App (Canonical)
- Type: Expo React Native app
- Purpose: Primary iOS app for development, simulator testing, and TestFlight builds
- Run: `pnpm ios` or `pnpm ios:simulator`
- Build: `pnpm ios:build:preview` / `pnpm ios:build:production`

### 2. `apps/macos` — Desktop WebView App (Canonical)
- Type: Electron wrapper
- Purpose: Native desktop shell that loads the web app (`apps/mail`)
- Run: `pnpm macos`

### 3. `apps/mail` — Web App (Canonical)
- Type: Next.js app
- Purpose: Main Todus web product

### 4. `apps/server` — Backend (Canonical)
- Type: Cloudflare Worker API
- Purpose: Auth, mail APIs, AI workflows

## Archived Apps (Do Not Build)

All non-canonical app implementations are archived under:

- `apps/archived/native`
- `apps/archived/webview-swift`
- `apps/archived/apple`

These are reference-only and intentionally removed from active root scripts.

## Command Policy

Use only:
- `pnpm ios*` for iPhone app work
- `pnpm macos` for desktop app work

Do not use archived app paths for active development.

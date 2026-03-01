# Apps Architecture Overview

## Canonical Runtime Targets

### iPhone
- App: `apps/ios`
- Stack: Expo + React Native + Expo Router
- Status: active, only supported iOS implementation

### Desktop (macOS)
- App: `apps/macos`
- Stack: Electron WebView wrapper
- Status: active, only supported desktop wrapper

### Web
- App: `apps/mail`
- Stack: Next.js
- Status: active

### Backend
- App: `apps/server`
- Stack: Cloudflare Worker (Hono + tRPC)
- Status: active

## Archived Implementations

To remove platform duplication and double-build confusion, legacy apps were archived:

- `apps/archived/native` (old RN CLI iOS/macOS/Android app)
- `apps/archived/webview-swift` (old SwiftUI WebView wrapper)
- `apps/archived/apple` (stale project remnants)

Archived apps are for reference only and are not part of the active app surface.

## Build Entry Points

- iOS: `pnpm ios`, `pnpm ios:simulator`, `pnpm ios:build:*`
- macOS: `pnpm macos`
- Web/backend: standard `pnpm dev`, `pnpm deploy:*`

`native:*` root scripts were removed to enforce a single active iOS and desktop path.

# Apps Architecture Overview

## Canonical Runtime Targets

### iPhone
- App: `apps/ios/Todus`
- Stack: Native SwiftUI (Xcode, Swift 6)
- Status: active, only supported iOS implementation

### Desktop (macOS)
- App: `apps/macos`
- Stack: Native SwiftUI shell scaffold
- Status: active, canonical desktop implementation

### Web
- App: `apps/mail`
- Stack: React Router v7 + Vite
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

- iOS: `bun ios`, `bun ios:simulator`, `bun ios:build:*`
- macOS: `cd apps/macos && xcodegen generate && open TodusMac.xcodeproj`
- Web/backend: standard `bun dev`, `bun deploy:*`

`native:*` root scripts were removed to enforce a single active iOS and desktop path.

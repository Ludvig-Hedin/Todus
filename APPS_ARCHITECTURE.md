# Apps Architecture Overview

> Last updated: March 27, 2026

## Canonical Runtime Targets

### iPhone
- **App:** `apps/ios/Todus`
- **Stack:** Native SwiftUI (Xcode, Swift 6, iOS 18+)
- **Bundle ID:** `com.ludvighedin.todus`
- **Status:** Active — unified app with Tasks, Email, Calendar, AI, Home dashboard

### Web
- **App:** `apps/mail`
- **Stack:** React Router v7 + Vite + Cloudflare Workers
- **URL:** todus.app
- **Status:** Active

### Backend
- **App:** `apps/server`
- **Stack:** Cloudflare Worker (Hono + tRPC + Durable Objects + PostgreSQL)
- **Status:** Active

### Desktop (macOS)
- **App:** `apps/macos`
- **Stack:** Native SwiftUI (Xcode, Swift 6, macOS 15+)
- **Status:** Active — shell scaffold with sidebar navigation and placeholder panes

## Archived Implementations

Legacy apps moved to `apps/archived/` for reference only:

- `apps/archived/native` — old React Native CLI iOS/macOS/Android app
- `apps/archived/webview-swift` — old SwiftUI WebView wrapper
- `apps/archived/apple` — stale project remnants

**Do not use** archived code in new development.

## Build Entry Points

- **iOS:** Open `apps/ios/Todus/Todus.xcodeproj` in Xcode, or `pnpm ios:simulator`
- **macOS:** `cd apps/macos && xcodegen generate && open TodusMac.xcodeproj`
- **Web + Backend:** `pnpm dev` (Turborepo), `pnpm deploy:frontend`, `pnpm deploy:backend`
- **Database:** `pnpm docker:db:up`, `pnpm db:generate`, `pnpm db:migrate`

# Apps Architecture Overview

> Canonical runtime-target map. Last updated: 2026-05-27.
>
> For the full agent landing context, see [AGENT_CONTEXT.md](AGENT_CONTEXT.md).

## Canonical Runtime Targets

### Web (active frontend)
- **App:** `apps/web` (bun filter `@zero/web`)
- **Stack:** React Router v7 + Vite + Cloudflare Workers (SSR)
- **Routes:** marketing pages, auth, `/mail/*` product, `/settings/*`, `/developer`, `/blog/*`, `/compare/*`, `/share/*`, `/g/*`
- **URL:** todus.app
- **Status:** Active — all current frontend work goes here.

### Backend
- **App:** `apps/server` (bun filter `@zero/server`)
- **Stack:** Cloudflare Worker (Hono + tRPC + Drizzle ORM + Hyperdrive PostgreSQL + Durable Objects + Workflows + KV + R2 + Queues)
- **Worker name:** `todus-server-v1` (`apps/server/wrangler.jsonc`)
- **Status:** Active

### iPhone
- **App:** `apps/ios/Todus`
- **Stack:** Native SwiftUI (Xcode, Swift 6, iOS 18+)
- **Bundle ID:** `com.ludvighedin.todus`
- **Deep link scheme:** `todus://`
- **Status:** Active — unified app with Home, Tasks, Email, Calendar, AI, Docs, Meetings, Settings

### macOS
- **App:** `apps/macos/TodusMac`
- **Stack:** Native SwiftUI (Xcode, Swift 6, macOS 15+)
- **Distribution:** DMG uploaded to Cloudflare R2 by `scripts/build-mac-dmg.sh`; surfaced on `/downloads`
- **Status:** Active — feature parity with iOS across Home, Tasks, Email, Calendar, AI (with local MLX), Docs, Meetings, Settings

### Android (scaffolded only)
- **App:** Expo scaffold reachable via `bun android`
- **Status:** Not actively shipped. Parity capture script exists (`bun parity:screenshots:capture:android:auto`).

## Read-only / Archived

| Path | Note |
|---|---|
| `apps/mail/` | Legacy React Router frontend. Superseded by `apps/web/`. **Do not edit.** Root scripts `bun build:frontend` / `bun deploy:frontend` still target this — use `bun run --filter=@zero/web build|deploy` to ship the active app. |
| `apps/archived/native` | Old React Native CLI iOS/macOS/Android app |
| `apps/archived/webview-swift` | Old SwiftUI WebView wrapper |
| `apps/archived/apple` | Stale project remnants |
| `apps/archived/archived-rn` | Older RN snapshot |

**Do not use** archived code in new development.

## Build Entry Points

| Target | Command(s) |
|---|---|
| iOS | `bun ios` (open Xcode project), `bun ios:simulator`, `bun ios:build:preview`, `bun ios:build:production` |
| macOS | `bun macos`, or `./scripts/build-mac-dmg.sh` for a signed DMG uploaded to R2 |
| Web | `bun run --filter=@zero/web build`, `bun run --filter=@zero/web deploy`, `bun dev` (dev server) |
| Backend | `bun deploy:backend`, `bun dev` (dev server) |
| Database | `bun docker:db:up`, `bun db:generate`, `bun db:migrate`, `bun db:push`, `bun db:studio` |

`apps/macos/TodusMac.xcodeproj` is checked in directly — no `xcodegen` step needed.

## Design System

Each platform owns a `DesignSystem/` folder for color / typography / radius / spacing / motion tokens:

- Web: `apps/web/app/globals.css`
- iOS: `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift`
- macOS: `apps/macos/TodusMac/DesignSystem/MacTheme.swift`

Cross-platform parity is tracked in [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) (canonical tokens) and [DESIGN_SYSTEM_INCONSISTENCIES.md](DESIGN_SYSTEM_INCONSISTENCIES.md) (gap analysis). Live in-app viewers exist on all three platforms behind the `TODUS_ALLOWLISTED_EMAILS` / `VITE_TODUS_ALLOWLISTED_EMAILS` allowlist.

When you add or change a token, update **all three platform sources + DESIGN_SYSTEM.md** in the same change.

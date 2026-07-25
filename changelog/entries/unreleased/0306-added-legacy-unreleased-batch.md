---
id: 0306
title: "Added — legacy unreleased batch"
status: unreleased
category: Added
source: CHANGELOG.md
---

### Added

- macOS DMG build script (`scripts/build-mac-dmg.sh`) — archives, signs, packages, and uploads to Cloudflare R2 with pre-flight safety checks
- `apps/macos/ExportOptions.plist` for Xcode Development-signed archive export
- `/downloads` page updated: Mac download button now serves DMG from Cloudflare R2 with internal tester guidance
- **macOS HuggingFace cache detection** — new `HuggingFaceCacheConnector` scans both the app's HF cache (`Documents/huggingface/models`) and the user's external cache (`~/.cache/huggingface/hub`) for MLX-shaped (`mlx-community/*`) model directories. Surfaces them in Settings → Local Models under a "Connected (HuggingFace)" section so users can adopt models they already pulled outside the app. Tapping "Use" routes the chat service through the MLX runtime via a synthesized `LocalModel` for uncurated repos (using the existing `MacAIChatService` routing path, alongside the Ollama tag heuristic).
- **Dedicated native auth session** — `/api/auth/mobile-token` now inserts a separate `session` row when handing off to iOS/macOS so the native app appears as its own "Active Session" in settings instead of inheriting the web OAuth session. Falls back to the web session token if the DB insert fails. (`apps/server/src/main.ts`)
- **Cross-platform settings sync** — `aiTone` (professional/casual/concise), `taskRemindersEnabled`, `calendarRemindersEnabled` moved from `@AppStorage`-only into `userSettingsSchema` so they sync across web/iOS/macOS via the existing settings tRPC route. (`apps/server/src/lib/schemas.ts`)
- **Web design system tokens** — explicit `--space-{xs,sm,md,lg,xl,2xl}` scale (4/8/12/16/24/32 px) matching iOS/macOS, plus `--surface-primary`, `--surface-secondary`, `--surface-sheet` aliases. Motion durations rebalanced: `--motion-duration-base` 220→250 ms, `--motion-duration-slow` 320→350 ms. (`apps/web/app/globals.css`)
- **Settings page polish** — `/settings/design-system` refactored to share the `_components-manifest.tsx` source of truth (377-line slimdown); `/settings/notifications` slimmed by ~160 lines using the new token aliases; `/settings/billing` + `/settings/ai` updated to use semantic surfaces; web `Button` component tightened for dark-mode contrast.
- **Playwright web parity capture** — new `scripts/parity/capture-web-playwright.mjs` headlessly captures gated screens (`/settings/design-system` etc.) using `PLAYWRIGHT_SESSION_TOKEN` cookies. Wired into `pnpm parity:screenshots:capture:web`.
- **Parity script surface filters** — `check-screenshots.mjs`, `capture-ios-deeplink.mjs`, `capture-ios-interactive.mjs`, `capture-macos-electron.mjs` all gained `--surface` / `--platform` / `--allow-missing` flags. The macOS capture script now builds + launches `apps/macos/TodusMac` via `xcodebuild` (Electron wrapper retired).

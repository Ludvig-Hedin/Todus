---
id: 0302
title: "Design system alignment pass — accent canonicalization, motion + spacing tokens, macOS contrast fixes, screenshot infra"
status: archived
category: Fixed
release_date: 2026-05-24
source: CHANGELOG.md
---

## [2026-05-24] Design system alignment pass — accent canonicalization, motion + spacing tokens, macOS contrast fixes, screenshot infra

Cross-platform alignment pass closing 6 tracked gaps in `DESIGN_SYSTEM_INCONSISTENCIES.md`. iOS adopted as canonical reference (visually cleanest per user direction). Five parallel slices:

- **Accent palette canonicalized to muted "refined editorial" values.** iOS shipped TWO different accent systems (legacy `accentColor(for:)` function with muted hex `#3873d9`, and the new `AppTheme.Accents` enum with vibrant `#407AFF`). Legacy function deleted; `AppTheme.Accents` updated to canonical muted RGB: blue(0.22,0.45,0.85) indigo(0.35,0.32,0.78) teal(0.18,0.52,0.55) green(0.25,0.55,0.32) orange(0.78,0.48,0.18) rose(0.72,0.28,0.35). Single source of truth. macOS dark-mode brightening normalized to consistent ~7-8% across all 6 colors (was inconsistent 6-17%). Web `ACCENT_COLORS` already at canonical hex.
- **macOS pill contrast + motion easing fix.** Segmented selected pill dark `white: 0.22 → 0.30` — lifts visibly above track (`0.15`) instead of barely separating. `Motion.fast` switched from `.easeOut` to `.snappy(0.15)` and `Motion.slow` from `.snappy` to `.spring(0.35, 0.85)` so motion feel matches iOS. Added missing `sheetBackground` (light 0.978 / dark 0.135) and `surfaceSecondary` (light 0.96 / dark 0.205) tokens — were referenced by intent across mac code but had no canonical token.
- **Web motion duration alignment.** `--motion-duration-base: 220ms → 250ms` and `--motion-duration-slow: 320ms → 350ms` to match iOS `Motion.base` / `slow`. `fast: 150ms` already matched.
- **Web spacing tokens (4 / 8 grid)** — `apps/web/app/globals.css`. New `--space-xs / sm / md / lg / xl / 2xl` (4 / 8 / 12 / 16 / 24 / 32 px) on `:root`, exposed via Tailwind v4 `@theme inline` as `--spacing-*` so `p-md`, `gap-xl`, `mt-2xl` work. Mirrors iOS `Spacing` / macOS `MacTheme.spacing*` scale. Plus semantic surface aliases `--surface-primary / -secondary / -sheet` alongside shadcn's `--card / --accent / --popover` for cross-platform naming clarity. Light-mode parity audit complete — web `:root` runs ~2% lighter than iOS canonical with intentional cool tint from shadcn lineage; documented and accepted in `DESIGN_SYSTEM_INCONSISTENCIES.md`.
- **Screenshot regression infrastructure for DS viewers** — `scripts/parity/capture-web-playwright.mjs` (new, headless Playwright via the existing `packages/testing` install — no new dep added), `capture-macos-electron.mjs` rewritten for the native `TodusMac` SwiftUI shell (the old Electron path was dead), manifest extended with 7 DS slugs + `macos` platform, `--surface` / `--platform` / `--allow-missing` filters on `check-screenshots.mjs`. Capture commands: `pnpm parity:screenshots:capture:{web,ios,macos:auto} -- --surface design-system`. Three blockers documented (web auth tokens not in CI, iOS deep-link router missing `/settings/*`, macOS DS sidebar not deep-linkable) — infra ready, baselines deferred until those land. No pixel diff yet (presence-only check); `pixelmatch`/`odiff` is the natural next step.

Also resolved in this pass (not visually impactful but tracked):

- **Naming aliases on web** — `--surface-primary` etc. give cross-platform readers a shared vocab without breaking shadcn names.
- **Web outline button parity** — `outline` variant dropped opaque `bg-background` for `bg-transparent` so it reads correctly over card surfaces, matching iOS / macOS.

**Two new tracked followups** (not blocking this pass):

- iOS still has dual accent stores (`@AppStorage("ios_accent_color")` synced to backend + `services.accentPreference` local-only). Both render canonical palette now but don't cross-update. Recommend consolidating around the backend-synced path.
- iOS typography not centralized like macOS — `.font(.system(...))` literals scatter across views. macOS centralizes via `cardTitleFont` / `metaFont` etc. Worth porting.

Validation: `xcodebuild` succeeded on both Todus (iOS) and TodusMac (macOS); `oxlint --deny-warnings` clean on touched web files; `tsc --noEmit` introduced zero new errors. iOS build has pre-existing errors in `AppServices.swift:940-956` (parallel session work on `syncSetting` / `OneFieldInput` — unrelated to this pass).

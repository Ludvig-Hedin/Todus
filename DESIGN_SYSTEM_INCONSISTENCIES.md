# Design System Inconsistencies

> Cross-platform gap analysis. Companion to [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md).
> Last updated: 2026-05-24.

This document tracks known visual / token drift across `apps/web`, `apps/ios/Todus`, and `apps/macos/TodusMac`. Resolved items stay listed (with status) so future changes know what was previously fixed.

---

## Status legend

- ✅ **Resolved** — gap closed
- 🟡 **Tracked** — known gap with chosen owner / followup
- 🔴 **Open** — gap not yet addressed

---

## Resolved gaps — 2026-05-24 alignment pass

### ✅ Accent palette canonicalized to muted "refined editorial" values

**Before:** iOS shipped TWO accent systems with different values — a legacy `accentColor(for:)` function (muted: blue `#3873d9`) AND a recently-added `AppTheme.Accents` enum (vibrant: blue `#407AFF`). macOS used the muted values. Web used the muted hex strings. Same name, three different colors.

**After:** iOS legacy `accentColor(for:)` deleted. Single source of truth = `AppTheme.Accents` enum, updated to the canonical muted RGB:

| Name | Canonical RGB | Hex |
|------|---------------|-----|
| Blue | (0.22, 0.45, 0.85) | `#3873d9` |
| Indigo | (0.35, 0.32, 0.78) | `#5952c7` |
| Teal | (0.18, 0.52, 0.55) | `#2e858c` |
| Green | (0.25, 0.55, 0.32) | `#408c52` |
| Orange | (0.78, 0.48, 0.18) | `#c77a2e` |
| Rose | (0.72, 0.28, 0.35) | `#b84759` |

iOS callers route through `AccentPreference.color` / `AppTheme.Accents.<name>`. macOS dark-mode lifts normalized to consistent ~7-8% brightening across all 6 (was inconsistent 6-17%). Web `ACCENT_COLORS` already at canonical hex — no change needed.

### ✅ macOS segmented pill dark contrast

**Before:** Selected pill dark `white: 0.22` over track `white: 0.15` = 0.07 lift — barely visible.

**After:** Pill dark `white: 0.30` = 0.15 lift over track. Matches iOS canonical contrast.

### ✅ macOS motion easing aligned to iOS feel

**Before:** macOS `fast` used `.easeOut(0.15)`, `slow` used `.snappy(0.35)`. Perceptually softer than iOS `.snappy` / `.spring`.

**After:** `fast = .snappy(0.15)`, `slow = .spring(0.35, 0.85)`. Matches iOS. Durations unchanged. `base` and `spring` were already correct.

### ✅ Web motion durations aligned

**Before:** Web `--motion-duration-base: 220ms` and `slow: 320ms` — 30ms faster than iOS `Motion.base` (250ms) and `slow` (350ms).

**After:** `base: 250ms`, `slow: 350ms`. `fast: 150ms` already matched.

### ✅ Web spacing tokens (4 / 8 grid)

**Before:** Web relied on raw Tailwind classes (`gap-1`, `gap-2`). Values matched iOS / macOS Spacing scale but were not exposed as semantic tokens.

**After:** `--space-xs / sm / md / lg / xl / 2xl` CSS custom properties on `:root` mirror the iOS / macOS Spacing scale (4 / 8 / 12 / 16 / 24 / 32 px). Exposed via Tailwind v4 `@theme inline` as `--spacing-*` so `p-md`, `gap-xl`, `mt-2xl` resolve to the aligned scale.

### ✅ Token naming semantic aliases on web

**Before:** Web `--card` ↔ iOS `surfacePrimary` ↔ macOS `surfaceCard`. Same role, three different names. Cross-platform readers had to mentally map.

**After:** Web exposes `--surface-primary` / `--surface-secondary` / `--surface-sheet` as aliases over shadcn's `--card` / `--accent` / `--popover`. Tailwind utilities `bg-surface-primary` etc. work. Shadcn names preserved for compatibility — aliases sit alongside.

### ✅ Light mode parity audited

**Audited:** Web `:root` (HSL-derived) vs iOS canonical light values. Drift findings:

| Token | Web hex | iOS hex | Drift |
|-------|---------|---------|-------|
| `--background` | `#f5f5f5` | `#f0f0f0` (iOS `0.94`) | +2.1% lighter |
| `--card` | `#ffffff` | `#ffffff` (iOS `1.0`) | match |
| `--popover` | `#ffffff` | `#f9f9f9` (iOS `0.978`) | +2.2% lighter |
| `--accent` | `#f4f4f6` (hue 240) | `#f5f5f5` (iOS `0.96`) | -0.4% + cool tint |
| `--border` | `#e8e8eb` (hue 240) | `#ebebeb` (iOS `0.92`) | -1.2% + cool tint |

**Decision:** Web HSL preserved. Drift is < 2.5% and the cool tint (hue 240) is intentional shadcn lineage. Changing would ripple through every shadcn component visual. Future overhaul (e.g. moving to Tailwind v4 `@theme` exclusively) is the moment to converge.

### ✅ macOS missing `surfaceSecondary` + `sheetBackground` tokens

**Before:** macOS had no analog for iOS `surfaceSecondary` (badge / recessed bg) or `sheetBackground` (modal canvas). Mac code reached past `MacTheme` to inline `Color(white: ...)` literals.

**After:** Both tokens added to `MacTheme` with proper light/dark values matching iOS counterparts:
- `sheetBackground = Color(light: 0.978, dark: 0.135)`
- `surfaceSecondary = Color(light: 0.96, dark: 0.205)`

### ✅ Web outline button parity

**Before:** Web `outline` variant added `bg-background` — opaque. iOS / macOS outline buttons are transparent over their containers.

**After:** Outline variant now `bg-transparent` + hover state only. Matches iOS feel.

---

## Resolved gaps — 2026-05-21 design system pass

### ✅ Dark mode background was inconsistent and too dark

iOS `#0C0C0C` → `#1c1c1e` (white 0.109). macOS `~#141414` → `#1c1c1e`. Surfaces step in ~0.04–0.06 white increments. Web HSL preserved (~#161618).

### ✅ iOS missing accent color palette

`AppTheme.Accents` enum + `AccentPreference` storage added. Picker row in `AppearanceSettingsView`.

### ✅ Radius scale tier mismatch

Unified six-tier scale: `xs / sm / md / lg / xl / 2xl` → `7 / 12 / 14 / 16 / 18 / 24` pt.

### ✅ Transition durations were scattered hardcoded literals

`Motion.fast / base / slow` tokens on each platform. Migration sweep across all callsites.

### ✅ Hardcoded color literals bypassing tokens

Refactored `MacSettingsView:124`, `MacCalendarView:294`, `MacAssistantPanel:490`, `SettingsView.swift:1758`, `CalendarViewController.swift:55` to token references.

### ✅ Web has a `glass` button variant mirroring iOS `LiquidGlassButtonStyle`

`Button variant="glass"` in `apps/web/app/components/ui/button.tsx`. Backdrop blur + saturated lift, hairline white border, soft layered shadow, press scales to 0.97 + brightness lift. Default radius `--radius-md` (14px) matches iOS `Radius.control`.

### ✅ DS viewer gallery is manifest-driven

`apps/web/app/(routes)/settings/design-system/_components-manifest.tsx` exposes typed `COMPONENT_MANIFEST`. Adding a new shadcn primitive is one PR-sized diff in the manifest.

---

## Tracked gaps (followups)

### 🟡 Screenshot regression suite — infra in place, capture blockers remain

Infrastructure landed (`scripts/parity/capture-web-playwright.mjs`, rewritten macOS capture for native shell, manifest extended with DS slugs + macos platform, `--surface` / `--platform` filters on check script). Three blockers prevent fully-automated baseline capture:

1. **Web auth tokens not in CI** — DS viewer is allowlist-gated. Need `PLAYWRIGHT_SESSION_TOKEN` + `PLAYWRIGHT_SESSION_DATA` from a live signed-in session. No mock today.
2. **iOS deep-link router missing `/settings/*`** — `TodosApp.swift` `.onOpenURL` handles only `auth-callback`, `link-callback`, `share`, `mailto`. ~30 LOC fix to add a pending-route enum that `SettingsView` reads on appear.
3. **macOS DS sheet sidebar not deep-linkable** — `MacDesignSystemView` uses SwiftUI `selection` binding with no AppleScript hook. Section-by-section requires `--interactive`.

**No pixel diff yet** — `check-screenshots.mjs` is presence-only. Adding `pixelmatch` or `odiff` is the natural next step.

**Recommended CI addition** (not yet wired):
```yaml
- run: pnpm parity:screenshots:check -- --surface design-system
```
Trigger on PRs touching `globals.css`, `AppTheme.swift`, `MacTheme.swift`, or the 3 DS viewer files.

### 🟡 iOS dual accent stores

iOS has TWO independent accent selection paths:
- `@AppStorage("ios_accent_color") accentColorKey: String` — used by picker in Preferences section, synced to backend `accountSetting.accentColor`.
- `services.accentPreference: AccentPreference` — used by picker in Appearance section, persisted under `Keys.accentPreference` defaults, NOT synced to backend.

Both render the same canonical palette now (post-2026-05-24 pass) but they don't cross-update. Picking blue in Appearance leaves Preferences unchanged.

**Followup:** consolidate into one store. Recommend keeping the backend-synced `@AppStorage` path and bridging `AccentPreference` to wrap it.

### 🟡 Web light-mode bg ~2% lighter + cool tint vs iOS

Documented in "Light mode parity audited" above. Drift < 2.5%, intentional shadcn lineage. Address in future overhaul.

### 🟡 Naming differences remain on Swift side

- iOS `surfacePrimary` ↔ macOS `surfaceCard` (same role, different name)
- iOS `surfaceSecondary` ↔ macOS `surfaceHover` (now both exist after 2026-05-24)
- Toast: iOS `ToastOverlay` vs macOS `MacToastOverlay`

Cross-reference table in [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) provides the mapping. Mechanical rename across all callsites deferred — not visually impactful.

### 🟡 iOS typography not centralized like macOS

macOS exposes `greetingFont`, `dateFont`, `sectionHeaderFont`, `cardTitleFont`, `cardSubtitleFont`, `metaFont` on `MacTheme`. iOS uses inline `.font(.system(size: 13, weight: .medium))` literals across views. macOS strategy is cleaner.

**Followup:** add equivalent typography helpers to `AppTheme` and sweep iOS callsites.

---

## Open gaps (not yet addressed)

### 🔴 Storybook / Ladle equivalent not in place for web

DS viewer page is the closest thing to a component playground but is single-route and lives behind the allowlist. Designers external to allowlist can't preview components in isolation.

**Followup:** evaluate Ladle (smaller bundle than Storybook) if external designers join the team.

### 🔴 No build-time enforcement of token usage

Nothing prevents a new PR from adding `Color(white: 0.1)` inline instead of using `AppTheme` / `MacTheme` tokens. Same on web — hardcoded hex literals can slip in. Lint rule would help.

**Followup:** add `eslint` / `swiftlint` rule that flags raw color literals outside `DesignSystem/` folders.

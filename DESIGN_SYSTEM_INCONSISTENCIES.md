# Design System Inconsistencies

> Cross-platform gap analysis. Companion to [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md).
> Last updated: 2026-05-21.

This document tracks known visual / token drift across `apps/web`, `apps/ios/Todus`, and `apps/macos/TodusMac`. Resolved items stay listed (with status) so future changes know what was previously fixed.

---

## Status legend

- ✅ **Resolved** — gap closed by the 2026-05-21 design system pass
- 🟡 **Tracked** — known gap with a chosen owner / followup
- 🔴 **Open** — gap not yet addressed

---

## Resolved gaps (2026-05-21 design system pass)

### ✅ Dark mode background was inconsistent and too dark

**Before:**
- iOS canvas: `#0C0C0C` (`white: 0.05`) — much too inky vs reference Apple system dark
- macOS canvas: `~#141414` (`white: 0.08`) — closer to Apple but still darker than canonical
- Web: HSL-based dark theme; different scale entirely

**After (canonical):** Apple system dark `#1c1c1e` (`white: 0.109`) on iOS + macOS. Surfaces step in ~0.04–0.06 white increments. Web HSL preserved (it already reads as `~#161618` and the readability sweep showed no need to lift).

### ✅ iOS missing accent color palette

**Before:** macOS and web both shipped the 6-color accent palette (blue / indigo / teal / green / orange / rose) selectable in Settings → Appearance. iOS had no equivalent — accents were hardcoded `Color.primary` for "accentBlue" and inline RGB literals on auth + onboarding surfaces.

**After:** `AppTheme.Accents` enum + `AccentPreference` storage on `AppServices`. Picker row added to `AppearanceSettingsView`. Hex values match macOS / web exactly.

### ✅ Radius scale tier mismatch

**Before:** web had 3 tiers (`--radius-sm/md/lg`), iOS had 6 (`chip / inline / compact / control / row / card / composer`), macOS had 5 (`pillRadius / compactRadius / buttonRadius / rowRadius / cardRadius`). Different intermediate sizes meant the same conceptual "card" rendered with different curvature on different platforms.

**After:** unified six-tier scale (`xs / sm / md / lg / xl / 2xl` → `7 / 12 / 14 / 16 / 18 / 24` pt). Web exposes via CSS vars; iOS keeps `Radius` enum names with matching values; macOS keeps its naming with matching values.

### ✅ Transition durations were scattered hardcoded literals

**Before:** iOS used `.snappy(duration: 0.15)`, `.easeInOut(0.2)`, `.spring(...)` inline across ~15 callsites. macOS the same on `MacSidebarView`, `MacRootView`, `MacToastOverlay`. Web had `duration-150 / 200 / 300 / 500` literals scattered across 18+ shadcn/ui files. No global tuning point.

**After:** `Motion.fast / base / slow` tokens on each platform. Token migration sweep across all callsites. Future tuning happens in one place per platform.

### ✅ Hardcoded color literals bypassing tokens

**Before:** several files reached past `AppTheme` / `MacTheme` to inline `Color(white: …)` literals — making them invisible to token sweeps and likely to drift.

**After:** refactored to token references:
- `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift:124` → `MacTheme.contentBackground`
- `apps/macos/TodusMac/Views/Calendar/MacCalendarView.swift:294` → `MacTheme.segmentedTrack`
- `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift:490` → `MacTheme.contentBackground`
- `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift:1758` → `UIColor(white: 0.109, alpha: 1)` (matches new canonical bg)
- `apps/ios/Todus/Todus/Features/Calendar/CalendarViewController.swift:55` → `UIColor(white: 0.109, alpha: 1)`

---

## Tracked gaps (followups)

### 🟡 Token naming differs across platforms

- Web `--card` ↔ iOS `surfacePrimary` ↔ macOS `surfaceCard`
- Web `--accent` (subtle) ↔ iOS `surfaceSecondary` ↔ macOS `surfaceHover`
- Toast component: iOS `ToastOverlay` vs macOS `MacToastOverlay` — same role, different prefix

**Why we haven't unified:** changing the names is mechanically large and ripples through every callsite. The values match — only the labels differ. The cross-reference table in [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) provides the mapping.

**Followup:** if we ever rebuild the web token layer (e.g. moving from CSS vars to Tailwind v4 `@theme` exclusively), align the names then.

### 🟡 Spacing scale on web uses Tailwind defaults, not the 4 / 8 grid explicitly

iOS / macOS expose `Spacing.xs/sm/md/lg/xl/2xl`. Web relies on raw Tailwind classes (`gap-1`, `gap-2`, etc.) — the values match (4 / 8 / 12 / 16 / 24 / 32) but they are not exposed as semantic tokens.

**Followup:** if web grows custom spacing semantics (e.g. settings row padding), expose them as CSS vars to mirror the Swift enums.

### 🟡 Web has no equivalent of the iOS `LiquidGlassButtonStyle`

iOS 26 Liquid Glass button on iOS. Web has `glassmorphism`-style utilities available via Tailwind but no first-class component. macOS does not need this style — the desktop aesthetic is more restrained.

**Followup:** evaluate whether web wants a glass button variant for hero CTAs. Currently `Button variant="main"` covers the prominent-CTA role.

### 🟡 Light mode parity has not been audited

The 2026-05-21 pass focused on dark mode (where the drift was most visible). Light-mode token values across platforms have not been cross-checked beyond confirming they exist.

**Followup:** schedule a light-mode parity audit before any landing page or settings UI work that runs in light mode by default.

### 🟡 Web component gallery in DS viewer does not auto-discover new shadcn/ui primitives

The viewer renders an explicit list. Adding a new primitive in `components/ui/` requires updating the gallery manually.

**Followup:** consider a build-time generator that scans `components/ui/` and emits a gallery manifest.

---

## Open gaps (not yet addressed)

### 🔴 No screenshot regression suite for the design system viewer

Token changes could silently regress the viewer's own rendering. We rely on manual eyeball comparison.

**Followup:** wire `pnpm parity:screenshots:check` to capture the design system viewer on all three platforms.

### 🔴 Storybook / Ladle equivalent not in place for web

The DS viewer page is the closest thing to a component playground but is single-route and lives behind the allowlist. Designers external to allowlist can't preview components in isolation.

**Followup:** evaluate Ladle (smaller bundle than Storybook) if external designers join the team.

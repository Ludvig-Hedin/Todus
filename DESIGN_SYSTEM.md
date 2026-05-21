# Design System

> Canonical token reference and cross-platform mapping for the Todus design system.
> Last updated: 2026-05-21.

Todus ships three frontends (`apps/web`, `apps/ios/Todus`, `apps/macos/TodusMac`). This document is the source of truth for the tokens (colors, typography, radius, spacing, motion) they share. When you add or change a token, **update both the platform source files and this document in the same PR**.

Live in-app viewers (gated to `TODUS_ALLOWLISTED_EMAILS` allowlist):

| Platform | Path |
|----------|------|
| Web | `/settings/design-system` |
| iOS | Settings → Developer → Design System |
| macOS | Settings → Developer → Design System |

Sources of truth:

| Platform | File |
|----------|------|
| Web | `apps/web/app/globals.css` |
| iOS | `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift` |
| macOS | `apps/macos/TodusMac/DesignSystem/MacTheme.swift` |

Allowlist mechanism:

- Swift (iOS + macOS): `packages/swift-auth/Sources/TodusAuth/TodusDeveloperAccess.swift` — `TodusDeveloperAccess.isAllowlisted(email:)`. Set `TODUS_ALLOWLISTED_EMAILS` env var (comma-separated, lowercased).
- Web: `apps/web/lib/developer-access.ts` — `isAllowlisted(email)`. Set `VITE_TODUS_ALLOWLISTED_EMAILS` env var (Vite-prefixed mirror of the Swift var).

---

## Aesthetic

"Refined editorial" — restrained monochrome surfaces with a muted accent system. Generous spacing, soft continuous radii, no harsh dividers, smooth-but-tactile motion. Inspired by Apple's modern visual language (iOS 18 / macOS Sequoia / apple.com 2024-2026) without copying it.

---

## Color tokens — dark mode

All platforms target Apple's system dark background (`#1c1c1e`, `Color(white: 0.109)`) as the canonical baseline. Surface lift follows ~0.04–0.06 white steps.

| Token role | Web (CSS var, HSL) | iOS (`UIColor(white:)`) | macOS (`Color(white:)`) |
|------------|---------------------|--------------------------|--------------------------|
| Background (canvas) | `--background` | `0.109` (`backgroundTop/Bottom`) | `0.109` (`contentBackground`) |
| Sheet / modal surface | — | `0.135` (`sheetBackground`) | `0.125` (`emptyStateSurface`) |
| Surface (card) | `--card` | `0.165` (`surfacePrimary`) | `0.135` (`surfaceCard`) |
| Surface (hover/secondary) | `--accent` (subtle) | `0.205` (`surfaceSecondary`) | `0.17` (`surfaceHover`) |
| Segmented track (recessed) | — | `0.185` (`segmentedTrack`) | `0.15` (`segmentedTrack`) |
| Segmented selected pill | — | `0.30` (`segmentedSelectedPill`) | — |
| Chat user bubble | — | `0.23` (`chatUserBubbleFill`) | — |
| Border (subtle) | `--border` | `cardBorder` (separator @ 0.20) | `cardBorder` |
| Destructive | `--destructive` (`#D93036`) | `danger` (`rgb(0.85, 0.24, 0.22)`) | (matches) |
| Calendar "now" marker | — | `calendarNow` (`rgb(0.92, 0.23, 0.21)`) | — |

Web canonical light/dark CSS custom properties live in `apps/web/app/globals.css:30-103`. iOS canonical dark values are in `AppTheme.swift:112-176`. macOS canonical dark values are in `MacTheme.swift:45-94`.

## Color tokens — light mode

| Token role | iOS (`UIColor(white:)`) | macOS (`Color(white:)`) |
|------------|--------------------------|--------------------------|
| Background (canvas) | `0.94` | `0.955` |
| Sheet / modal | `0.978` | — |
| Surface (card) | `1.0` | (white) |
| Surface (secondary) | `0.96` | `0.945` |

Web light values follow shadcn defaults; see `globals.css` `:root` block.

---

## Accent palette

Six muted accent options, identical hex across platforms. User-selectable via Settings → Appearance.

| Name | RGB (0-1) | Hex | Web file:line | iOS | macOS |
|------|-----------|-----|---------------|-----|-------|
| Blue | (0.25, 0.48, 1.00) | `#407AFF` | `appearance/page.tsx:36` | `AppTheme.Accents.blue` | `MacTheme.accentColor(for: .blue)` |
| Indigo | (0.35, 0.34, 0.84) | `#5957D6` | `appearance/page.tsx:37` | `AppTheme.Accents.indigo` | `MacTheme.accentColor(for: .indigo)` |
| Teal | (0.20, 0.68, 0.78) | `#33ADC7` | `appearance/page.tsx:38` | `AppTheme.Accents.teal` | `MacTheme.accentColor(for: .teal)` |
| Green | (0.20, 0.72, 0.40) | `#33B866` | `appearance/page.tsx:39` | `AppTheme.Accents.green` | `MacTheme.accentColor(for: .green)` |
| Orange | (0.98, 0.55, 0.20) | `#FA8C33` | `appearance/page.tsx:40` | `AppTheme.Accents.orange` | `MacTheme.accentColor(for: .orange)` |
| Rose | (0.93, 0.32, 0.46) | `#ED5275` | `appearance/page.tsx:41` | `AppTheme.Accents.rose` | `MacTheme.accentColor(for: .rose)` |

Storage keys: web — `ACCENT_COLOR_STORAGE_KEY` in `localStorage`. iOS / macOS — `accentPreference: AccentPreference` on `AppServices` / `MacAppServices` (UserDefaults-backed).

---

## Radius scale

Unified six-tier scale across platforms (radii in **points** for SwiftUI, **px** for web).

| Tier | Value | Use | Web CSS var | iOS | macOS |
|------|-------|-----|-------------|-----|-------|
| `xs` / `chip` | 7 | Tags, badges, chips | `--radius-xs` | `Radius.chip` | `pillRadius` |
| `sm` / `compact` | 12 | Inline cards, compact blocks | `--radius-sm` | `Radius.compact` | `compactRadius` |
| `md` / `control` | 14 | Buttons, inputs, search fields | `--radius-md` | `Radius.control` | `buttonRadius` |
| `lg` / `row` | 16 | List rows, medium tiles | `--radius-lg` | `Radius.row` | `rowRadius` |
| `xl` / `card` | 18 | Primary cards, sheets, prominent surfaces | `--radius-xl` | `Radius.card` | `cardRadius` |
| `2xl` / `composer` | 24 | Composer chrome, large floating surfaces | `--radius-2xl` | `Radius.composer` | — |

Buttons may also use `rounded-full` on web for pill shapes.

---

## Spacing scale

iOS / macOS use a 4 / 8 px grid: `4, 6, 8, 12, 16, 20, 24, 28, 32`. Web uses Tailwind defaults (`0, 0.5, 1, 1.5, 2, 3, 4, 6, 8, 12, 16` × 4 px).

| iOS / macOS | Web (Tailwind class) | px |
|-------------|----------------------|-----|
| `Spacing.xs` | `gap-1` | 4 |
| — | `gap-1.5` | 6 |
| `Spacing.sm` | `gap-2` | 8 |
| `Spacing.md` | `gap-3` | 12 |
| `Spacing.lg` | `gap-4` | 16 |
| — | `gap-5` | 20 |
| `Spacing.xl` | `gap-6` | 24 |
| — | `gap-7` | 28 |
| `Spacing.2xl` | `gap-8` | 32 |

macOS settings-specific: `settingsSectionSpacing: 28`, `settingsRowVerticalPadding: 11`, `settingsRowHorizontalPadding: 14`.

---

## Typography

| Style | iOS | macOS | Web (Tailwind) |
|-------|-----|-------|----------------|
| Display / greeting | 22pt semibold | `greetingFont` (22pt semibold) | `text-2xl font-semibold` |
| Page title | 18pt bold | 24pt regular (`calendarTitle`) | `text-xl font-semibold` |
| Section header | 13pt semibold | `sectionHeaderFont` (12pt semibold) | `text-sm font-semibold` |
| Body / card title | 15pt semibold | `cardTitleFont` (13pt medium) | `text-base` |
| Body secondary | 13pt regular | `cardSubtitleFont` (12pt regular) | `text-sm text-muted-foreground` |
| Meta / caption | 11pt medium | `metaFont` (11pt medium) | `text-xs` |

Font families:
- Web: Geist Variable (sans) + Geist Mono. Letter-spacing tightened (`-0.014em` body, `-0.02em` headings).
- iOS / macOS: SF Pro system fonts. Weights: 400 / 500 / 600.

---

## Motion tokens

Unified naming across platforms. Map ad-hoc durations to these tokens whenever you touch animation code.

| Token | Web | iOS | macOS |
|-------|-----|-----|-------|
| `fast` | `--motion-duration-fast: 150ms` | `Motion.fast = .snappy(0.15)` | `Motion.fast = .easeOut(0.15)` |
| `base` | `--motion-duration-base: 220ms` | `Motion.base = .snappy(0.25)` | `Motion.base = .snappy(0.25)` |
| `slow` | `--motion-duration-slow: 320ms` | `Motion.slow = .spring(0.35, 0.85)` | `Motion.slow = .snappy(0.35)` |
| `spring` | — | (use `Motion.slow`) | `Motion.spring = .spring(0.32, 0.85)` |
| Standard easing | `--motion-easing-standard: cubic-bezier(0.2, 0, 0, 1)` | (implicit in `snappy`) | (implicit) |
| Emphasized easing | `--motion-easing-emphasized: cubic-bezier(0.16, 1, 0.3, 1)` | — | — |

**When to use:**
- `fast` — hover transitions, micro press feedback, tooltip fades
- `base` — dropdown / popover open-close, sidebar disclosure, tab swaps, panel slides
- `slow` — sheet presentations, large structural transitions, toast entry

---

## Component cross-reference

| Component | Web | iOS | macOS |
|-----------|-----|-----|-------|
| Primary button | `components/ui/button.tsx` (variant: `default`) | `AppPrimaryButtonStyle` in `AppTheme.swift:596` | (use system Button + `.tint`) |
| Secondary button | `button.tsx` (`secondary`) | `AppSecondaryButtonStyle` in `AppTheme.swift:623` | — |
| Liquid glass button | — | `LiquidGlassButtonStyle` in `AppTheme.swift:675` | — |
| Card | `components/ui/card.tsx` | (compose w/ `rowFill` + `cardBorder` + `Radius.card`) | (compose w/ `surfaceCard` + `cardBorder` + `cardRadius`) |
| Dropdown menu | `components/ui/dropdown-menu.tsx` | SwiftUI `Menu` | SwiftUI `Menu` |
| Dialog / modal | `components/ui/dialog.tsx` | SwiftUI `.sheet` | SwiftUI `.sheet` |
| Side panel | `components/ui/sheet.tsx` | (custom) | (custom) |
| Inline refresh badge | — | `InlineRefreshBadge` | `MacInlineRefreshBadge` |
| Toast | (sonner via `toast.tsx`) | `ToastOverlay` | `MacToastOverlay` |
| Brand icons | (lucide-react) | `BrandIcons.swift` | (system SF Symbols) |

---

## How to change

### Add or modify a color

1. Pick a token role from the table above (or add a new one).
2. Edit the platform source file:
   - Web: `apps/web/app/globals.css` — `:root` (light) and `.dark` blocks
   - iOS: `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift` — `enum AppTheme`
   - macOS: `apps/macos/TodusMac/DesignSystem/MacTheme.swift`
3. Update the row in this doc.
4. Spot-check the change in the in-app design system viewer.

### Add or modify a motion token

1. Choose `fast` / `base` / `slow` semantics — don't introduce a new tier unless absolutely necessary.
2. Web: edit `:root` motion vars in `globals.css`; sweep usages to reference the var via Tailwind utility `duration-(--motion-duration-fast)` etc.
3. iOS / macOS: edit `enum Motion` in `AppTheme.swift` / `MacTheme.swift`. Replace inline `.snappy(...)`, `.easeOut(...)`, `.spring(...)` with `AppTheme.Motion.*` / `MacTheme.Motion.*`.

### Add a new component

1. Build the component on each platform with native primitives (shadcn/ui on web, SwiftUI Views on iOS/macOS).
2. Register it in the Components section of the design system viewer.
3. Add a row to the Component cross-reference table above.

### Add the design system viewer to a new platform

1. Implement the allowlist check (mirror `TodusDeveloperAccess.isAllowlisted`).
2. Gate a settings entry behind it.
3. Render Colors / Typography / Radius / Spacing / Motion / Components sections — pull values from the platform's source-of-truth file so the viewer self-updates as tokens evolve.

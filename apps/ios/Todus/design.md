# Todus — Design System

## Brand Identity

Todus is a unified productivity app (email + tasks + calendar + AI assistant) for iOS and macOS. The design language is **Apple-native first** — minimal custom styling, heavy reliance on system components, SF Pro typography, and SF Symbols iconography. The visual identity is "liquid glass" — translucent materials, subtle depth, and ultra-clean surfaces.

---

## Colors

### Philosophy
Follow Apple's Human Interface Guidelines. Use system semantic colors as the primary palette. Custom colors are accent-only.

### Primary Palette
| Token | Value | Usage |
|-------|-------|-------|
| `accent` | System Blue (`Color.accentColor`) | Primary actions, selected states, links |
| `backgroundTop` | System Background | Main view backgrounds |
| `surfacePrimary` | Secondary System Background | Cards, input fields, elevated surfaces |
| `surfaceSecondary` | Tertiary System Background | Nested containers, selected pill states |
| `cardBorder` | Separator color (0.15 opacity) | Subtle borders on cards and inputs |

### Semantic Colors
| Token | Usage |
|-------|-------|
| `.primary` | Main text, active tab icons |
| `.secondary` | Subtext, inactive tab icons, timestamps |
| `.tertiary` | Placeholder text, empty states |
| `AppTheme.mutedText` | Deemphasized UI elements |

### Dark Mode
- **Dark mode first** — all designs start in dark mode
- Use `.ultraThinMaterial` for tab bars and overlays (liquid glass effect)
- Active tab icon: `.primary` (white in dark mode) — NO blue accent on tab icons
- System materials automatically adapt to light/dark

### Calendar Colors
- Event dots use the calendar's native `cgColor` — respect the user's Apple Calendar color choices

---

## Typography

### Font Family
**SF Pro** (system default) — never use custom fonts.

### Type Scale
| Style | Size | Weight | Usage |
|-------|------|--------|-------|
| Title Large | 28pt | Bold | Page greetings ("Good morning") |
| Title | 20pt | Semibold | Section headers, sheet titles |
| Body | 17pt | Medium | Input fields, primary content |
| Subhead | 15pt | Medium/Semibold | Section labels, dates |
| Caption | 14pt | Medium | Search bars, secondary text, timestamps |
| Caption 2 | 13pt | Semibold | Pill labels, type selectors |
| Micro | 12pt | Semibold/Bold | Folder tags, counts, badges |

### Letter Spacing
- Tight tracking (`-0.1`) on small tags and badges
- Default tracking everywhere else

---

## Icon System

### SF Symbols (mandatory)
All icons must be SF Symbols. No custom icon assets.

### Tab Bar Icons
| Tab | Symbol | Style |
|-----|--------|-------|
| Home | `house.fill` | Filled |
| Tasks | `checklist` | Regular |
| Email | `envelope.fill` | Filled |
| Calendar | `calendar` | Regular |
| AI (chat) | `sparkles` | Regular |
| Create (FAB) | `plus` | Regular |

### Action Icons
| Action | Symbol |
|--------|--------|
| Settings | `gearshape` |
| Search | `magnifyingglass` |
| Sort | `arrow.up.arrow.down` |
| Clear | `xmark.circle.fill` |
| Compose | `square.and.pencil` |
| Reply | `arrowshape.turn.up.left` |
| Archive | `archivebox` |
| Delete | `trash` |
| Mark read | `envelope.open` |
| Mark unread | `envelope.badge` |
| Voice | `mic` |
| Attach | `paperclip` |

### Create Sheet Type Icons
| Type | Symbol |
|------|--------|
| Auto | `wand.and.stars` |
| Task | `checklist` |
| Event | `calendar.badge.plus` |
| Email | `envelope` |

---

## Border Radius

| Context | Radius | Style |
|---------|--------|-------|
| Cards, inputs, surfaces | 16pt | `.continuous` |
| Inner segments (pills in pickers) | 12pt | `.continuous` |
| Pill buttons, tags | Capsule | `Capsule()` |
| FAB button | Circle | `Circle()` |
| Sheet corners | System default | Let SwiftUI handle it |

---

## Spacing System

### Base Unit: 4pt

| Token | Value | Usage |
|-------|-------|-------|
| `xs` | 2pt | Inner pill padding |
| `sm` | 4pt | Icon-to-text gap in compact rows |
| `md` | 8pt | Between list items, between icon groups |
| `lg` | 12pt | Between sections in a card |
| `xl` | 16pt | Page horizontal margins, section spacing |
| `2xl` | 20pt | Sheet content padding |
| `3xl` | 24pt | Between major sections on Home tab |

### Page Margins
- Horizontal: 16pt (all screens)
- Top: 12pt (below safe area)
- Bottom: variable (account for tab bar height ~60pt)

---

## UI Principles

### 1. Native First
- Use system components (NavigationStack, Sheet, Menu, TextField) before custom ones
- Use `.ultraThinMaterial` for translucent surfaces, not custom blur
- Use system haptics and animations
- Use `EKEventViewController` and `EKEventEditViewController` for calendar event details

### 2. Minimal Custom Styling
- Cards: single subtle border + surfacePrimary fill — no shadows except on FAB
- Buttons: `.plain` style with custom backgrounds — no system chrome
- No gradients (except system materials)
- No custom shadows on cards (only on the floating FAB)

### 3. Dark Mode Priority
- Design and test in dark mode first
- Ensure all custom colors work in both modes via semantic colors
- Use `.opacity()` modifiers for active/selected states, not hardcoded colors

### 4. Liquid Glass Feel
- Tab bar: `.ultraThinMaterial` background
- AI chat sheet: large detent with system material dimming
- Create sheet: medium detent with drag indicator
- Subtle blur and translucency — let content show through

### 5. No Labels on Navigation
- Tab bar: icons only, no text labels
- Keep UI ultra-clean and spacious
- Selected state communicated purely through color (primary vs secondary)

### 6. Consistent Interaction Patterns
- Swipe left on list items: destructive action (archive/delete)
- Swipe right: mark read/unread
- Long press: context menu
- Pull to refresh: on scrollable lists
- Sheet dismiss: swipe down or tap outside

---

## Component Reference

### AppTheme (existing)
All colors, spacing, and font references live in `DesignSystem/AppTheme.swift`. New views should reference `AppTheme.*` tokens rather than hardcoding values.

### Animations
- State transitions: `.snappy(duration: 0.18)` for micro-interactions
- View transitions: `.snappy(duration: 0.3)` for tab/page changes
- Sheet presentations: system default (spring-based)

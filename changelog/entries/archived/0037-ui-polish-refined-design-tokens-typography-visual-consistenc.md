---
id: 0037
title: "UI Polish — Refined Design Tokens, Typography & Visual Consistency"
status: archived
category: Changed
release_date: 2026-03-26
source: CHANGELOG.md
---

## [2026-03-26] UI Polish — Refined Design Tokens, Typography & Visual Consistency

### Design Token Refinements (globals.css)

- **Softened foreground colors**: Light mode foreground moved from near-pure-black `hsl(240 10% 3.9%)` to softer `hsl(240 6% 13%)`. Dark mode foreground eased to `hsl(0 0% 93%)`.
- **Warmed backgrounds**: Light bg shifted to `hsl(0 0% 99%)`, dark bg to `hsl(240 4% 7.5%)`. Static hex colors use slightly warm grays instead of pure blacks.
- **Tightened typography**: Base letter-spacing set to `-0.011em`, headings to `-0.02em`. Body line-height `1.5`, heading line-height `1.2`. Font smoothing enabled globally.
- **Softer borders/rings**: Border and ring values use slightly more neutral hues with lower saturation.

### Component Updates

- **button.tsx**: Text tightened to `13px`, transitions smoothed to `150ms`.
- **card.tsx**: Rounded from `2xl` to `xl`, shadow softened. Card title from `2xl` to `lg`. Padding tightened from `p-6` to `p-5`.
- **input.tsx**: Height from `h-10` to `h-9`, rounded from `xl` to `lg`, text `13px`.
- **settings-card.tsx**: Removed hardcoded `panelLight/panelDark` for `transparent`. Tighter spacing.

### Sidebar Refinements

- **Removed purple upgrade button** (`#8B5CF6` → `mainBlue`). Tighter spacing and smaller text.
- **Compose button**: Uses `mainBlue` token. Smoother transition.
- **Sidebar padding**: Reduced from `px-4` to `px-3` for tighter layout.
- **Nav section titles**: Changed from `13px` to `11px uppercase tracking-wide` for clear visual hierarchy.
- **Hover states**: Replaced hardcoded `bg-subtleWhite`/`dark:bg-[#202020]` with `bg-accent` token.

### Navigation & User Area

- **Replaced 20+ hardcoded hex colors** (`dark:bg-[#131313]`, `dark:bg-[#141414]`, `text-black dark:text-white`, etc.) with semantic tokens (`bg-popover`, `bg-card`, `text-foreground`, `bg-background`).
- **Tighter user info section**: Reduced spacing between name, email, and verification badge.

### Login Page

- **Tighter layout**: Narrowed max-width to `340px`, reduced padding and heading sizes.
- **Typography**: Headings from `2xl` to `xl`, links from `text-xs` to `11px`.
- **Showcase panel**: Rounded from `2.5rem` to `2xl`, softened border/shadow.

### Mail List (thread items)

- **Hover**: Replaced `bg-offsetLight`/`dark:bg-primary/5` with `bg-accent/60` + `transition-colors`.
- **Action bar**: Tightened from `rounded-xl p-1 gap-1` to `rounded-lg p-0.5 gap-0.5` with softer shadow.
- **Unread dot**: Smaller (`1.5` from `2`), uses `mainBlue` token.
- **Date text**: Reduced to `11px`.
- **Content preview**: Tighter margins, `12px` text.
- **Removed all hardcoded tooltip backgrounds** (`bg-white dark:bg-[#1A1A1A]`).

### Thread Display

- **Container**: Replaced `bg-panelLight dark:bg-panelDark` with `bg-card`.
- **All action buttons**: Replaced `bg-white dark:bg-[#313131]`/`hover:bg-gray-100 dark:hover:bg-[#404040]` with `bg-card hover:bg-accent`.
- **Reply button**: Cleaner token-based styling.
- **Empty state**: Tighter text sizes, token-based colors.

### Settings Layout

- **Replaced all hardcoded border/bg colors** with `border-border/60` and `bg-card`.
- **Slightly tighter padding** and reduced shadow.

### iOS Refinements

- **AppTheme.swift**: Slightly adjusted dark mode background from `0.04` to `0.05` white, surface values nudged 1% lighter. Border opacities reduced for subtlety. Shadow reduced from `0.08` to `0.06`.
- **EmailInboxView**: Inbox header font `28→24` with tighter tracking. Search bar corners `16→12`, thinner border.
- **EmailThreadView**: Subject font `17→16` with tracking. Reply bar height `44→42`, corners `14→12`.

### Files Updated

- `apps/mail/app/globals.css`
- `apps/mail/components/ui/button.tsx`
- `apps/mail/components/ui/card.tsx`
- `apps/mail/components/ui/input.tsx`
- `apps/mail/components/ui/app-sidebar.tsx`
- `apps/mail/components/ui/nav-main.tsx`
- `apps/mail/components/ui/nav-user.tsx`
- `apps/mail/components/ui/settings-content.tsx`
- `apps/mail/components/settings/settings-card.tsx`
- `apps/mail/components/mail/mail-list.tsx`
- `apps/mail/components/mail/thread-display.tsx`
- `apps/mail/components/mail/mail.tsx`
- `apps/mail/app/(auth)/todus/login/page.tsx`
- `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift`

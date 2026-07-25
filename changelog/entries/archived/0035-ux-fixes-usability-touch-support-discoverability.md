---
id: 0035
title: "UX Fixes — Usability, Touch Support & Discoverability"
status: archived
category: Fixed
release_date: 2026-03-26
source: CHANGELOG.md
---

## [2026-03-26] UX Fixes — Usability, Touch Support & Discoverability

### Critical Fixes

- **Security settings**: Replaced non-functional 2FA toggle and Delete Account button with clear "Coming soon" state. Prevents users from thinking they've enabled security features that don't exist yet. (`settings/security/page.tsx`)
- **Thread action toolbar touch support**: Action buttons (star, archive, delete) now visible when a thread is selected/focused, not just on hover. Touch devices (tablets, phones) can now access these core actions. Added `@media (pointer: coarse)` CSS rule for broader touch support. (`mail-list.tsx`, `globals.css`)

### High-Impact Improvements

- **CC/BCC toggle visibility**: Replaced invisible plain-text Cc/Bcc buttons with styled toggle buttons that show active state (blue highlight when enabled). Much more discoverable in compose view. (`email-composer.tsx`)
- **Keyboard shortcuts overlay**: New `?` key shortcut opens a grouped, scrollable dialog showing all keyboard shortcuts organized by scope (Navigation, Global, Mail List, Thread, Compose). Replaces the old behavior of navigating away to settings. (`keyboard-shortcuts-dialog.tsx`, `hotkey-provider-wrapper.tsx`)
- **Context-sensitive empty states**: Mail list empty state now shows "No results found" with "clear filters" action when searching, vs. "No emails in this folder yet" when the folder is genuinely empty. (`mail-list.tsx`)

### Medium Fixes

- **iOS swipe-to-go-back**: Restored native swipe-back gesture in `EmailThreadView` by using `.navigationBarBackButtonHidden(true)` instead of `.toolbar(.hidden)`. Custom back button still renders, but iOS swipe gesture now works. (`EmailThreadView.swift`)

### Verified Working (no changes needed)

- **Undo toasts**: Archive/delete already have undo toasts with delayed execution — confirmed working via `createPendingAction` in `use-optimistic-actions.ts`.
- **Connections page**: Legitimate user-facing feature (manage connected email accounts), not debug info.
- **Category selection**: Uses dropdown with checkmarks — clear selected state already present.

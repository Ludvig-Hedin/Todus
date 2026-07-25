---
id: 0189
title: "Fix — Sender avatar transparent background bleed-through + fallback priority"
status: archived
category: Fixed
release_date: 2026-04-04
source: CHANGELOG.md
---

## [2026-04-04] Fix — Sender avatar transparent background bleed-through + fallback priority

- [Fix] iOS/macOS: Added white background circle behind loaded avatar images so transparent logos (Slack, GitHub, etc.) no longer show the colored initials circle bleeding through behind them
- [Fix] iOS/macOS/Web: Reordered local favicon fallback chain to prioritize Google's favicon service (`s2/favicons?sz=128`) — same source Gmail uses, highest coverage — before direct `/apple-touch-icon.png` and `/favicon.ico` fetches
- **Files:** `apps/ios/Todus/Todus/Features/Email/SenderAvatarView.swift`, `apps/macos/TodusMac/Views/Email/MacEmailInboxView.swift`, `apps/mail/components/ui/bimi-avatar.tsx`

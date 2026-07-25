---
id: 0186
title: "Feature — Unread dot repositioned + People view mode + avatar fixes"
status: archived
category: Fixed
release_date: 2026-04-04
source: CHANGELOG.md
---

## [2026-04-04] Feature — Unread dot repositioned + People view mode + avatar fixes

### Unread indicator moved to right of subject (iOS, macOS, Web)

- [UI] Moved blue unread dot from left of avatar to right of subject line across all platforms
- Emails now stretch correctly without the left-side dot misaligning the avatar column
- **Files:** `EmailRowView.swift`, `MacEmailInboxView.swift`, `mail-list.tsx`

### People view mode (iOS, macOS)

- [Feature] Added Threads/People toggle in inbox header (icon-based segmented control)
- People mode groups emails by sender — shows avatar, name, email, thread count, unread badge
- Tapping a person shows their threads (iOS: push navigation, macOS: detail panel)
- **Files:** `EmailInboxView.swift`, `MacEmailInboxView.swift`

### Avatar transparent background fix + fallback priority

- [Fix] iOS/macOS: White background behind loaded avatar images prevents colored initials bleeding through transparent logos
- [Fix] All platforms: Google favicon service prioritized in local fallback chain for better icon coverage
- **Files:** `SenderAvatarView.swift`, `MacEmailInboxView.swift`, `bimi-avatar.tsx`

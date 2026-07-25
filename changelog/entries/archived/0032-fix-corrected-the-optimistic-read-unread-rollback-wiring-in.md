---
id: 0032
title: "Fix — Corrected the optimistic read/unread rollback wiring in the native iOS swipe and thread-detail mutations"
status: archived
category: Fixed
release_date: 2026-03-11
source: CHANGELOG.md
---

[2026-03-11] [Fix] Corrected the optimistic read/unread rollback wiring in the native iOS swipe and thread-detail mutations so the new triage controls compile cleanly without changing their behavior. Architectural safety fix. (apps/ios/src/features/mail/SwipeableThreadRow.tsx, apps/ios/src/features/mail/ThreadDetailPane.tsx).

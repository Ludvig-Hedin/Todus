---
id: 0187
title: "Fix — Inbox People view polish, thread AI timestamp, French grammar"
status: archived
category: Fixed
release_date: 2026-04-04
source: CHANGELOG.md
---

## [2026-04-04] Fix — Inbox People view polish, thread AI timestamp, French grammar

- [Enhancement] iOS `EmailInboxView`: Extracted `buildSenderGroups(from:)`; view mode control exposes VoiceOver labels + selected state; People/threads UI unchanged (already wired).
- [Fix] iOS `EmailThreadView`: Summary attribution line uses `assistantContextLoadedAt` (set when assistant context loads) instead of `Date()` on every render.
- [i18n] `fr.json`: Corrected broken elisions (`d'courriel` → `de courriel`, etc.) and send-failure / shortcuts strings.
- **Files:** `EmailInboxView.swift`, `EmailThreadView.swift`, `apps/mail/messages/fr.json`

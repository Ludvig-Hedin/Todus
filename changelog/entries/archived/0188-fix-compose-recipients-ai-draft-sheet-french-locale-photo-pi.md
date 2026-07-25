---
id: 0188
title: "Fix — Compose recipients, AI draft sheet, French locale, photo picker"
status: archived
category: Fixed
release_date: 2026-04-04
source: CHANGELOG.md
---

## [2026-04-04] Fix — Compose recipients, AI draft sheet, French locale, photo picker

- [Fix] iOS `EmailComposeView`: To field clears to `[]` when empty (matches CC/BCC); Photos picker resets selection after load, surfaces load/decode failures (alert + `AppLogger`), no silent `try?`.
- [Enhancement] iOS `EmailAIDraftSheet`: Replace vs append explicit (`EmailAIDraftInsertMode`); cancel streaming on sheet dismiss; `URLRequest` timeout 30s; `Origin` from `AppConfiguration.effectiveAppURL` (not hardcoded).
- [i18n] `apps/mail/messages/fr.json`: Standardized user-facing strings to **courriel** / **pourriel** terminology.
- **Files:** `EmailComposeView.swift`, `EmailAIDraftSheet.swift`, `apps/mail/messages/fr.json`

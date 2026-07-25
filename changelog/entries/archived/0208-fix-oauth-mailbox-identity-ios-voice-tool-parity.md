---
id: 0208
title: "Fix — OAuth mailbox identity + iOS voice tool parity"
status: archived
category: Fixed
release_date: 2026-04-24
source: CHANGELOG.md
---

## [2026-04-24] Fix — OAuth mailbox identity + iOS voice tool parity

- [Fix] `syncConnectionFromAccount` now resolves the connected mailbox from the OAuth account itself instead of `mail0_user.email`, which fixes multi-account Google linking/reconnect flows that were overwriting the wrong connection email/token pair.
- [Fix] Provider identity fallback is now provider-aware: Google uses `id_token` / OIDC userinfo, while non-Google providers fall back to the driver `getUserInfo()` path instead of calling Google endpoints with the wrong token type.
- [Fix] Connection expiry now stores the provider's actual `accessTokenExpiresAt` timestamp instead of adding that absolute timestamp to `Date.now()`, which previously pushed some connection expiry values decades into the future.
- [Fix] iOS voice chat now exposes the same supported task/calendar tool contract as text chat: removed unsupported `urgent` task priorities from voice tool schemas and added calendar update/delete tool declarations plus execution handlers.
- [Fix] iOS voice input stop-timeout now uses the latest partial transcript at timeout time instead of the stale transcript captured when the user tapped stop, so trailing words are no longer dropped when the recognizer final callback arrives late.
- **Files:** `apps/server/src/lib/auth.ts`, `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`, `apps/ios/Todus/Todus/Features/Voice/VoiceInputButton.swift`

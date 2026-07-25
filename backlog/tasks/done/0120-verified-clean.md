---
id: 0120
title: "Verified clean"
status: done
tags: [code-review, code-review-backlog]
files: [apps/ios/Todus/Todus/Services/API/TodosAPIClient.swift, packages/swift-auth/Sources/TodusAuth/AuthService.swift, apps/macos/TodusMac/Views/Email/MacEmailInboxView.swift, apps/ios/Todus/Todus/Domain/MailAssistantModels.swift, new-website/relume/{home,download,legal,pricing}/components/Navbar11.jsx, apps/web/messages/en.json, apps/macos/TodusMac/Views/Calendar/CalendarTimeGridView.swift, apps/macos/TodusMac/Views/Calendar/MacCalendarView.swift]
created: 2026-05-02
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-02 — Full-repo Review

## Verified clean

- `d8d471c7` server pagination/parser regression fix — composite `(latestReceivedOn, id)` cursor correctly fixes the single-shard "exactly maxResults" pagination dead-end and the equal-timestamp cross-shard tie-skip. Backwards-compatible legacy parser path preserved.
- `apps/ios/Todus/Todus/Services/API/TodosAPIClient.swift` — `serializeJSONValue` correctly addresses NSInvalidArgumentException on `null`/fragment payloads. `EmailEmptyResponse` decodes from `{}` cleanly.
- `packages/swift-auth/Sources/TodusAuth/AuthService.swift` `preloadTokens()` — `nonisolated static` calling thread-safe `KeychainHelper.read` is sound.
- `apps/macos/TodusMac/Views/Email/MacEmailInboxView.swift` polling no longer triggers `forceSync` — fixes the destructive-resync-on-every-poll regression.
- `apps/ios/Todus/Todus/Domain/MailAssistantModels.swift` custom `init(from:)` with backward-compatible decoding for `aiLeadLine`/`threadKind`/`extractedCode`/`extractedReceipt` — correct pattern for staged backend rollout.
- `new-website/relume/{home,download,legal,pricing}/components/Navbar11.jsx` — pure formatting; all four files remain byte-identical post-change. (4-way duplication is its own debt; leaving for now.)
- `apps/web/messages/en.json` — only adds `pages.settings.general.location` keys; consistent with surrounding entries.
- `apps/macos/TodusMac/Views/Calendar/CalendarTimeGridView.swift` 1440-min cap — correct fix for visual overflow.
- `apps/macos/TodusMac/Views/Calendar/MacCalendarView.swift` `calshow:<refInterval>` URL — correct macOS scheme.
- `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift` `inFlightAction` race handling — correctly captures the action and only clears if it hasn't been replaced.

---

---
id: 0069
title: "iOS compose mention follow-up fixes"
status: archived
category: Fixed
release_date: 2026-03-28
source: CHANGELOG.md
---

## [2026-03-28] iOS compose mention follow-up fixes

### Summary

Reviewed the current iOS mention/slash-command compose changes and fixed two issues that were still present in the live code: email compose body focus was no longer wired to the existing `focusedField` state, and person mention suggestions could surface a different top-10 subset between runs because they were truncated before applying a stable sort.

### Updated Files

- `apps/ios/Todus/Todus/Features/Email/EmailComposeView.swift` — restored body-editor focus by passing explicit focus state into `RichComposerInput`, and sorted grouped senders by a stable name/email key before `prefix(10)`.
- `apps/ios/Todus/Todus/Features/Tasks/CaptureComposer.swift` — added optional focus control to `RichComposerInput` / `PasteHandlingTextInput` while preserving default auto-focus behavior for other existing callers.

### User-facing impact

- Opening compose now correctly places the keyboard in the body when `To` and `Subject` are already populated.
- Person mention suggestions in compose now remain stable and predictable across launches and rebuilds.

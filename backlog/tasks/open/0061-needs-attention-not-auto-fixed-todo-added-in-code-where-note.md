---
id: 0061
title: "Needs attention (not auto-fixed — TODO added in code where noted)"
status: open
priority: P3
tags: [ios, macos, bug-hunt, code-review-backlog]
files: [AppTheme.swift]
created: 2026-06-05
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-05 — Bug hunt (iOS + macOS changed files)

> Section overview — the individual findings from this section are separate items.

## Needs attention (not auto-fixed — TODO added in code where noted)

> Cleared false positives (verified NOT bugs): (1) `VoiceChatViewModel._micMutedAtomic` "never seeded" — `isMicMuted` only mutates in `toggleMute()`, which syncs the atomic under `micMutedLock` immediately (lines 195/198); they can't diverge. (2) `VoiceChatViewModel` converter status discarded — `convertedBuffer` is freshly allocated each tap (`frameLength` starts 0); the `error == nil && frameLength > 0` gate is adequate, no stale-buffer reuse. (3) `MLXInferenceService` AsyncThrowingStream "double-finish" — not a crash; `AsyncThrowingStream.Continuation.finish()` is idempotent (unlike `CheckedContinuation`). (4) `AppTheme.swift` color parsing — no hex parsing exists; all colors are `Color(red:green:blue:)` / `UIColor(white:)` literals already in range. (5) `AISourcesView`, `MeetingsListView`, `MoreSheetView`, `TaskRowView`, `CalendarSourcePickerView`, `CalendarAccountsView`, `EmailAutomationPolicyView`, `LocalModelsView` — read in full, clean.

---

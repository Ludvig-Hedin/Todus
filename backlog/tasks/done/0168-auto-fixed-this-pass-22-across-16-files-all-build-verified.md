---
id: 0168
title: "Auto-fixed this pass (22 across 16 files — all build-verified)"
status: done
tags: [ios, bug-hunt, code-review-backlog]
files: [Features/Tasks/CalendarTaskView.swift, Features/Search/GlobalSearchView.swift, Features/AI/CardViews.swift, Features/AI/ChatUISpecView.swift, Features/Email/EmailComposeView.swift, Features/Calendar/CalendarMonthView.swift, Features/Calendar/CalendarTimeGridView.swift, Services/Calendar/CalendarService.swift]
created: 2026-06-13
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Bug Hunt — 2026-06-13 — full iOS app (`/bug-hunt`)

## Auto-fixed this pass (22 across 16 files — all build-verified)

- `Features/Tasks/CalendarTaskView.swift` — inverted success haptic (fired on un-complete); capture `willBecomeDone` before toggle.
- `Features/Search/GlobalSearchView.swift` — event dot used packed-RGB `calendarColor` as a hue → meaningless color; now uses `calendarColorRed/Green/Blue` like every other call site.
- `Features/AI/CardViews.swift` — (1) robust `Color(hex:)` (3/6/8-char, validates hex, falls back) + new `rgbComponents`/`isLightHex`; (2) `LabelCardView` white tag-icon now luminance-aware (was invisible on light swatches); (3) WeeklyAgenda `ForEach` keyed by offset not duplicate date id; (4) empty-state messages for empty Calendar/Contact list cards (were blank bordered boxes).
- `Features/AI/CardViews.swift` (InlineComposeCard) — CC/BCC had no input field (couldn't add recipients) + Send dropped typed-but-unsubmitted addresses. Added per-target inputs (`toInput`/`ccInput`/`bccInput`) + flush-on-send.
- `Features/AI/ChatUISpecView.swift` — (1) button reads both `actionParams` and `params` (was silently no-op for `params` emitters); (2) card container uses visible `surfacePrimary`/`cardBorder` (was near-invisible `systemBackground.opacity(0.5)`).
- `Features/Email/EmailComposeView.swift` — (1) forward title showed "New Email" (now "Forward"); (2) `fromConnectionId` persisted+restored in autosave (was reverting to first account on reopen).
- `Features/Calendar/CalendarMonthView.swift` — month grid built with `bySetting:.day` (jumps months near boundaries/DST) → `byAdding`.
- `Features/Calendar/CalendarTimeGridView.swift` — grid-tap minutes now clamped to a valid slot (bottom/overscroll tap yielded hour 24 → silent no-op).
- `Services/Calendar/CalendarService.swift` — clamp sRGB-converted color components to 0...1 (P3 out-of-gamut rendered over-saturated).
- `Features/Settings/RemindersSetupView.swift` — toggle path now clears stale `permissionDenied` banner + runs outbound `syncExistingTasksToReminders` for parity with `connect()`.
- `Services/Voice/GeminiLiveProvider.swift` — input/output transcription emitted `isFinal:true` (REPLACE) → kept only last delta fragment; now `isFinal:false` (APPEND), finalized on `turnComplete`. Fixes both coordinator + VoiceChatViewModel consumers.
- `Services/Voice/AudioPlayerManager.swift` — odd-byte PCM chunk caused 1-byte heap overflow in `memcpy`; copy only frame-aligned bytes.
- `Features/Voice/VoiceChatViewModel.swift` — capture guard now accepts `.reconnecting` (was discarding started engine → mic-dead session).
- `Features/Tasks/InboxView.swift` — `.dueDate` sort now breaks `(nil,nil)` tie by `createdAt`, matching Board/Table/Calendar (rows no longer reshuffle across views).
- `Features/Docs/DocsListView.swift` — error empty-state Retry button + iPad detail pane loads a just-created doc not yet in `allDocs` (was stuck on "Select a document").
- `Features/Tasks/CaptureComposer.swift` — `needsHighlights` triggered on any `_` (lone underscore in email/file) forcing attributed rewrite → keyboard dismiss; now tests the actual paired-italic regex.
- `Domain/EmailModels.swift`, `Features/Email/EmailThreadView.swift` — removed unnecessary `nonisolated(unsafe)` (compiler warnings).

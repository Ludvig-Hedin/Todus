---
id: 0315
title: "Fixed — iOS performance & stability pass (lag / freezes / crashes)"
status: unreleased
category: Fixed
release_date: 2026-07-11
source: CHANGELOG.md
---

### Fixed — iOS performance & stability pass (lag / freezes / crashes), 2026-07-11

Bug-hunt + SwiftUI review pass targeting reported lag, freezes, and crashes. Findings were surfaced by parallel scout agents and each source-verified before fixing. Verified defects fixed:

- **Calendar edit froze the UI (fence hang)** — `CalendarViewController.dayView(dayView:didUpdate:)` called `EKEventStore.save()` synchronously on the main thread from a CalendarKit delegate callback; the store save is a synchronous XPC round-trip to the calendar daemon that can block for seconds. The save now runs on the existing `backgroundQueue` (matching how this file already creates the store and fetches events) and reloads on the main thread when it completes.
- **Scrolling an open email thread was laggy** — `MessageRow`'s "Copy message text" lived inside a `.contextMenu` ViewBuilder, which SwiftUI evaluates on every render, so the 5-pass regex HTML→plain-text strip (over bodies up to hundreds of KB) re-ran on every scroll frame. It now computes once per message off the main thread in `.task(id:)` and caches the result; `htmlToPlainText` is now `nonisolated static`.
- **Sending an AI chat message with attachments froze the UI** — `buildSerializedAttachments` (up to 12 MB of file reads + base64) ran on the `@MainActor`. It now serializes off-main into an `attachmentSnapshot` before the sync `buildPayload` (same "prep async, keep buildPayload sync" pattern already used for the calendar snapshot).
- **Attaching a photo to an email froze the UI** — the photo-library path JPEG-encoded + wrote to disk on the main thread; it now decodes/encodes/writes inside a detached task (the camera path is documented as a TODO — it needs the non-Sendable `UIImage` boxed).
- **Voice capture start/stop data race** — `engine` and `sendTimer` in `VoiceAudioCapture` were unlocked `var`s written from a background start closure and read/nilled from `stop()`; a rapid start→stop (double-tap mic) raced them, risking a crash or a mic that never released. Both are now guarded by a `stateLock`, and a stop that lands mid-start tears the booting engine down instead of publishing it.
- **Home dashboard recomputed too eagerly** — the "first task" prompt used an unbounded `@Query` that materialized every task in the DB just to check `.isEmpty` (now `fetchLimit = 1`); and `briefingFeedItems` (rebuild+dedup+rank) was re-invoked up to four times per render in `todayList` (now computed once).

Remaining lower-severity perf findings (Docs O(n²) tree render, AddToFolder per-keystroke fetch, Calendar now-line 60s relayout, GlobalSearch double-compute, camera photo-save) are logged in `CODE_REVIEW_BACKLOG.md`.

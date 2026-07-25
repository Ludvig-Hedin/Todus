---
id: 0286
title: "macOS regression sweep (post-parity)"
status: archived
category: Fixed
release_date: 2026-05-17
source: CHANGELOG.md
---

## [2026-05-17] macOS regression sweep (post-parity)

Final regression hunt over the parity-wave diff. 10 high-confidence findings, 6 parallel fixers, **BUILD SUCCEEDED** after each. Headlines:

- **Compose duplicate send with attachments** ([`MacEmailComposeView.swift`](apps/macos/TodusMac/Views/Email/MacEmailComposeView.swift)) — every email with an attachment was being POSTed to `mail.send` twice (once via `emailService.sendEmail`, again via `MacDraftService.send`). Now routes attachment sends exclusively through `MacDraftService.send` so each message ships once.
- **Voice transcripts overwritten by final delta** ([`GeminiLiveProvider.swift`](apps/macos/TodusMac/Services/Voice/GeminiLiveProvider.swift), [`VoiceSessionCoordinator.swift`](apps/macos/TodusMac/Services/Voice/VoiceSessionCoordinator.swift)) — Gemini Live emits incremental transcription chunks; the provider was tagging every chunk `isFinal: true`, so the coordinator's `userTranscript = text` replace path discarded all but the last fragment. Flipped to `isFinal: false` so the existing `+=` accumulator captures the full turn before `turnComplete`.
- **Calendar picker dead** ([`MacEventEditSheet.swift`](apps/macos/TodusMac/Views/Calendar/MacEventEditSheet.swift), [`CalendarService.swift`](apps/macos/TodusMac/Services/Calendar/CalendarService.swift)) — sheet bound `selectedCalendarSourceId` but `createEvent`/`updateEvent` ignored it and hardcoded `defaultCalendarForNewEvents`. Plumbed `calendarIdentifier:` through both; picker now persists.
- **Reminders sync oscillation** ([`AppleRemindersSyncService.swift`](apps/macos/TodusMac/Services/Reminders/AppleRemindersSyncService.swift)) — `upsert` unconditionally set `.pendingUpload` after every EKReminder save, including just-imported tasks, causing per-pass redundant upserts. Preserved `.synced` when the only change was attaching a freshly imported `reminderIdentifier`.
- **Reminders delete silent on EventKit errors** — `try?` swallowed failures; switched to `do/catch` with `AppLogger.shared.log` so deletions don't ghost.
- **`GoogleCalendarService.refresh` nuked newer in-flight task** — unconditional `inflightRefresh = nil` post-await; now guarded with identity check `if inflightRefresh == task`.
- **`MacAIChatService.send_email` dropped `connectionId`** — multi-account users always sent from the server-side default. Threaded `connectionId` through `MacSendEmailArgs` → `EmailDraft.fromConnectionId` → `SendEmailInput`.
- **`VoiceSessionCoordinator.attachAudioInput` captured stale continuation** — push-to-talk re-press cycled the continuation but the broker closure still held the old one. Now reads `self.audioSendContinuation` inside the MainActor hop so each yield uses the current stream.
- **Compose autosave phantom Cc/Bcc** ([`MacEmailComposeView.swift`](apps/macos/TodusMac/Views/Email/MacEmailComposeView.swift)) — explicit `clearedCc` / `clearedBcc` flags persisted alongside autosave so removed recipients don't resurrect on next open.
- **Gmail connect poll too short** ([`EmailService.swift`](apps/macos/TodusMac/Services/Email/EmailService.swift)) — extended 6×500ms → 12×750ms (9s budget) and softened the timeout message to "Still connecting — refresh in a moment to confirm." so slow backends don't report a false "Could not link your Gmail account".

Build: `xcodebuild -project apps/macos/TodusMac.xcodeproj -scheme TodusMac -destination 'platform=macOS' build` → **BUILD SUCCEEDED**.

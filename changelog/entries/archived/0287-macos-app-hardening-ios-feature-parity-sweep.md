---
id: 0287
title: "macOS app hardening + iOS feature parity sweep"
status: archived
category: Fixed
release_date: 2026-05-17
source: CHANGELOG.md
---

## [2026-05-17] macOS app hardening + iOS feature parity sweep

Multi-pass audit + remediation of `apps/macos/TodusMac`: critical/high bug fixes across mail, tasks, calendar, AI, voice, and auth; ~45 UX polish items; and a deliberate iOS → macOS parity push that closed the largest remaining gaps in Email, Calendar, Notifications, Tasks, and Search. Full integration `xcodebuild -project apps/macos/TodusMac.xcodeproj -scheme TodusMac -destination 'platform=macOS' build` → **BUILD SUCCEEDED** with zero errors.

**Critical / high bug fixes**

- [Meetings] **C1 duplicate top-level types** — resolved via existing `project.yml` exclusions; merged the secondary toolbar action into the canonical [`MacMeetingDetailView`](apps/macos/TodusMac/Views/Meetings/MacMeetingDetailView.swift) so only one symbol survives.
- [Docs] **C2 autosave reliability** ([`MacDocEditorPane`](apps/macos/TodusMac/Views/Docs/MacDocEditorPane.swift), [`MacDocsService.swift`](apps/macos/TodusMac/Services/Docs/MacDocsService.swift)) — flush on `onDisappear` + `onChange(docId)` + debounced title autosave + 3-state save indicator (saving / saved / failed-with-retry). Replaced the placeholder "Info coming soon" popover with a real word/char count + last-updated + copyable doc id view.
- [Auth] **C3 OAuth callback validation** ([`TodusMacApp.swift`](apps/macos/TodusMac/App/TodusMacApp.swift), [`MacAppServices.swift`](apps/macos/TodusMac/App/MacAppServices.swift)) — strict host check on `todus://` callbacks; queue inbound URLs until `ModelContainer` is ready so cold-launch deep links no longer drop into the void.
- [Voice] **C4 push-to-talk hotkey release** ([`HotkeyService.swift`](apps/macos/TodusMac/Services/Voice/HotkeyService.swift), [`VoiceSessionCoordinator.swift`](apps/macos/TodusMac/Services/Voice/VoiceSessionCoordinator.swift)) — tear down the `AudioInputBroker` on key-up and emit `sendActivityEnd()` end-turn frame so Gemini Live actually closes the turn instead of stalling.
- [Voice] **C5 dual `AVAudioEngine` crash** ([`MacVoiceChatPanel.swift`](apps/macos/TodusMac/Views/Voice/MacVoiceChatPanel.swift)) — replaced `.onAppear` with `.task` + awaited sequencing so the panel never starts a second engine while the global hotkey loop is still spinning down.
- [Tasks] **C6 Apple Reminders dedup + SwiftData `@MainActor` isolation** ([`AppleRemindersSyncService.swift`](apps/macos/TodusMac/Services/Tasks/AppleRemindersSyncService.swift)) — id-keyed dedupe + main-actor isolation on SwiftData mutations.
- [Tasks] **C7 delete sync** ([`MacTasksView.swift`](apps/macos/TodusMac/Views/Tasks/MacTasksView.swift)) — routed delete through `MacTaskSyncService` with a confirmation dialog so swipe-delete no longer drifts from the server.
- [Email] Bcc / `threadId` / `connectionId` / `draftId` now plumbed through send; idempotent flush with a 5-minute orphan window; pagination cursor race fixed; spinner guard against stale-page drops; sender match by header.
- [Tasks] 4xx vs 5xx retry policy with bounded max retries; word-boundary regex for compound intent parsing; [`FolderSyncService`](apps/macos/TodusMac/Services/Tasks/FolderSyncService.swift) enforces `syncedIds`; DST gap fix in recurrence math.
- [Calendar] Refresh-storm dedup; per-calendar `sourceId`; multi-day event overlap filter; scope-missing banner + reconnect CTA; Toggle race fix; `accessRole` plumbed end-to-end.
- [AI/Voice] `cancelStream` race closed via generation counter; tool exec cancellation gates; disconnect reentrancy guard; mic teardown on `.error`; serialized audio send queue with backpressure; `functionCall.id` fallback; `AudioPlayer._isPlaying` derived from buffer count; polling cross-group leak closed.
- [Auth] Restore-flash gone; profile fetch gated on session; folder `createdAt` drop fixed; settings now persists the full shape; voice context guard; OTP digit filter.

**iOS → macOS parity features (new)**

- [Email compose] **Attachments + signatures + live validation + rich text shortcuts** ([`MacEmailComposeView.swift`](apps/macos/TodusMac/Views/Email/MacEmailComposeView.swift), [`MacDraftService.swift`](apps/macos/TodusMac/Services/Email/MacDraftService.swift), [new] [`MacSignatureStore.swift`](apps/macos/TodusMac/Services/Email/MacSignatureStore.swift), [`MacSettingsView.swift`](apps/macos/TodusMac/Views/Settings/MacSettingsView.swift)) — `NSOpenPanel` attachment chips, base64 send through `MacDraftService.SendInput.attachments`; per-connection signatures stored in `MacSignatureStore` with a Settings card; live recipient validation; underline button + ⌘B / ⌘I / ⌘U shortcuts.
- [Email thread] **Verification code + tracking info chips, smart-action toolbar, snooze reminders** ([`MacEmailThreadView.swift`](apps/macos/TodusMac/Views/Email/MacEmailThreadView.swift), [`MacNotificationService.swift`](apps/macos/TodusMac/Services/Notifications/MacNotificationService.swift)) — regex-based verification-code chip with one-shot auto-copy; UPS / FedEx / USPS / order-number tracking chip; toolbar with Create Task / Create Event / Generate Reply (inline spinners); "Remind me about this…" with preset snooze + custom date picker → `scheduleEmailReminder`.
- [Calendar] **Native in-app event editor** ([new] [`MacEventEditSheet.swift`](apps/macos/TodusMac/Views/Calendar/MacEventEditSheet.swift)) — create / edit / delete inside the app (replaces Calendar.app delegation); "Open in Calendar.app" demoted to a context-menu fallback.
- [Notifications] **Full category + action registration** ([`MacNotificationService.swift`](apps/macos/TodusMac/Services/Notifications/MacNotificationService.swift), [`MacAppDelegate.swift`](apps/macos/TodusMac/App/MacAppDelegate.swift)) — `TASK_REMINDER`, `EMAIL`, `EMAIL_REMINDER`, `DUE_TASKS`, `AI_RESPONSE` categories with `TASK_COMPLETE`, `TASK_SNOOZE`, `ARCHIVE_EMAIL` actions; `UNUserNotificationCenterDelegate` implements `willPresent` (foreground banner) + `didReceive` routing for every type.
- [Tasks] **Recurrence + checklist + attachments** ([`MacTasksView.swift`](apps/macos/TodusMac/Views/Tasks/MacTasksView.swift), `TaskRecord` model) — RRULE-compatible None / Daily / Weekly / Monthly / Yearly; per-item checklist with live persistence; `NSOpenPanel` attachments copied to `Application Support/TaskAttachments/{taskId}/` with relative-path storage; JSON-backed accessors on `TaskRecord`.
- [Search] **Cross-entity search** ([`MacSearchView.swift`](apps/macos/TodusMac/Views/Search/MacSearchView.swift)) — tasks + emails + events + people with category chips (All / Tasks / Emails / Events / People), recent searches persisted via `@AppStorage` with a clear button, debounced 60-day calendar search, keyboard nav (↑ / ↓ / ⌘1–5 / ⌘↩), people derived from email senders.
- [Sharing] **Inbound `todus://share?slug=...` deep links** ([`TodusMacApp.swift`](apps/macos/TodusMac/App/TodusMacApp.swift), [`MacRootView.swift`](apps/macos/TodusMac/Views/MacRootView.swift), [new] [`MacSharedConversationView.swift`](apps/macos/TodusMac/Views/Sharing/MacSharedConversationView.swift)) — `handleIncomingURL` posts a `NotificationCenter` event; `MacRootView` presents the read-only sheet with password unlock + "Save to my conversations" via `shareService.importShare`.
- [Sidebar] **Restored Meetings entry** ([`MacSidebarView.swift`](apps/macos/TodusMac/Views/MacSidebarView.swift)).

**UX polish (~45 items)**

- Destructive confirmations (Log Out, task delete, folder delete) across Settings + Tasks.
- Toasts for: send failure, event creation, restore task, `openInCalendarApp` failure, `moveEvent` completion.
- Accessibility labels on icon-only buttons across Voice / Assistant / Calendar / Local Models.
- Notification routing via `onOpen` closure: `taskDue → tasks`, `importantEmail → thread`, `event → calendar`.
- Home briefing tap → thread deep link.
- Search clear (×), Meetings search clear, Local Models button-wrapped rows.
- 3-state save indicator, docs loading skeleton, grid / list segmented picker, outline row hover.
- Onboarding skip de-emphasized; Q&A button color reflects state; transcript "Show all (count)".
- Calendar all-day **Copy Date**; multi-day events now render in every spanned column.
- Empty search → **Create task '<query>'**.

**Files**

- New: [`MacSignatureStore.swift`](apps/macos/TodusMac/Services/Email/MacSignatureStore.swift), [`MacEventEditSheet.swift`](apps/macos/TodusMac/Views/Calendar/MacEventEditSheet.swift), [`MacSharedConversationView.swift`](apps/macos/TodusMac/Views/Sharing/MacSharedConversationView.swift) (plus `VoiceSessionCoordinator.swift` already untracked).
- Modified: ~35 files across `apps/macos/TodusMac/{App,Services,Views}/**` — see `git status` for the full list.

**Verification**

- `xcodebuild -project apps/macos/TodusMac.xcodeproj -scheme TodusMac -destination 'platform=macOS' build` → **BUILD SUCCEEDED** (zero errors, zero warnings introduced by this sweep).

**Manual follow-ups (out of scope this session)**

1. macOS Widget extension is wired in `project.yml`; needs a real-data verification pass through `MacWidgetUpdateManager`.
2. `WakeWordService` still a stub — Picovoice Porcupine integration deferred to Phase 1.5.
3. `GroupChatService` polling not yet migrated to the WebSocket Durable Object subscription (TODO in code).
4. `MacContentHeaderView` accessibility labels landed but top buttons still TODO real actions.
5. No XCTest target exists for macOS (only iOS has `TodusTests`). Stand up `TodusMacTests` as a follow-up.

Cross-reference: parity matrix added in [`PARITY_CHECKLIST.md`](PARITY_CHECKLIST.md) section **7) iOS ↔ macOS Feature Parity Matrix**.

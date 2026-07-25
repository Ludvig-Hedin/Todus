---
id: 0147
title: "Fix — Code quality and bug fixes across all platforms"
status: archived
category: Fixed
release_date: 2026-04-01
source: CHANGELOG.md
---

## [2026-04-01] Fix — Code quality and bug fixes across all platforms

Batch of ~50 fixes across iOS, macOS, web, and server layers covering security, stability, and UX.

### Server (`apps/server`)

- **env.ts**: Made `RECALL_WEBHOOK_SECRET` optional (`?`)
- **recall.ts**: Wrapped `JSON.parse` in try-catch for cleaner parse error messages
- **recall-webhook.ts**: Implemented full HMAC-SHA256 signature verification with production warning when secret is not set; made media and transcript inserts idempotent via `onConflictDoUpdate`/`onConflictDoNothing`; transcript event only sets status to `ready` when transcript fetch succeeds; handles null `recallSegmentId` segments separately to avoid dedup failures on retry; read body once to avoid double-consume
- **schema.ts**: Added `.unique()` to `recallMediaId` and `recallSegmentId` columns
- **Migration 0043**: Adds unique constraints for `recall_media_id` and `recall_segment_id`
- **meet.ts**: LIKE wildcard escaping for search; `scheduleBot` cleans up orphaned bot on DB failure; `deleteMeeting` checks for active bot before deleting; Invalid Date guard in `syncFromCalendar`; N+1 eliminated in `syncFromCalendar` — batch-fetch all existing meetings via `inArray` before the loop
- **mail-assistant.ts**: Added TODO comment for hardcoded UTC timezone

### Security

- **Severity: critical** — Fixed a SQL injection vulnerability in `searchMeetingTranscriptTool` in `apps/server/src/routes/agent/tools.ts`. The vulnerable transcript search path now escapes LIKE wildcards before building the query, preventing potential arbitrary query modification and transcript data exfiltration from attacker-controlled search input. Affected released versions: all released builds containing the original meetings transcript tool before the 2026-04-01 fix. Immediate upgrade required: **yes**.

### Fixes

- **tools.ts (agent)**: Fixed meeting tools type to avoid `undefined` in `ToolSet`

### iOS (`apps/ios`)

- **GroupChatView.swift**: URL-encodes invite token; surfaces `joinGroup`/`leaveGroup` errors via alerts; only clears token on success
- **ShareConversationSheet.swift**: Added `@MainActor` to `createLink()`; removed redundant `MainActor.run {}`
- **SharedConversationView.swift**: `unlock()` only sets `wrongPassword = true` for auth failures (401/403/password errors)
- **EmailThreadView.swift**: `handleDraftReply` only sets `assistantDraftSeed` when `result.created == true`; `AssistantPill` uses `Color(.systemBackground)` for dark mode
- **AIChatView.swift**: Share sheet uses `.sheet(item:)` with `ShareConversationID` to prevent blank sheet
- **SettingsView.swift**: Auto-send toggle shows confirmation dialog before enabling
- **MeetingDetailView.swift**: Added error alerts for `generateSummary`/`scheduleBot`; stable `@State AVPlayer`
- **MeetingsListView.swift**: Added error state with retry button
- **MeetingsService.swift**: Added `loadError` property; removed `private` from `GenerateSummaryResponse`

### macOS (`apps/macos`)

- **MailAssistantModels.swift**: Added `Sendable` to `MailAssistantSettingsResponse`/`Settings`; stable stored `id` for `MailAssistantNudge`
- **GroupChatService.swift**: Replaced all `apiClient!` force-unwraps with guard-let; `createGroup` matches by returned id; per-iteration `guard let self` in polling loop
- **ShareConversationService.swift**: Replaced all `apiClient!` force-unwraps with guard-let
- **MacEmailInboxView.swift**: Disabled nudge button when `threadIds.isEmpty`
- **MacEmailThreadView.swift**: `onDismiss` clears `assistantDraftSeed`; `handleDraftReply` only shows notice when draft NOT created; renamed "Extract tasks" → "Extract task"
- **CalendarService.swift**: `pruneFolderMap` guards against calendar permission revocation
- **MacAssistantPanel.swift**: Closes share panel when `currentConversationID` becomes nil
- **MacMeetingDetailView.swift**: Added error alerts; stable `@State AVPlayer`; `scheduleBot` returns Bool for error detection
- **MacMeetingsView.swift**: Added "Upcoming" category for future meetings beyond this week; added error state when `loadError` is set and list is empty (with Retry button)
- **MeetingsService.swift**: Added `loadError`; removed `private` from `GenerateSummaryResponse`

### Web (`apps/mail`)

- **mail-display.tsx**: Refresh button handler wrapped in try-catch with `toast.error`
- **chat/page.tsx**: Added `onError` handler to `saveConversation`; `handleDeleteConversation` moves `handleNewChat()` to `onSuccess`
- **search/page.tsx**: Safe date parsing with `isValid()` for thread and task dates
- **tasks/page.tsx**: Added `aria-label` to search and quick-add inputs; `quickAddValue` cleared only on mutation success; removed stale `setDetailTask` spread
- **settings/general/page.tsx**: Replaced `as never` TypeScript cast with `as any` + eslint-disable comment
- **calendar/page.tsx**: Fixed inaccurate "±1 day buffer" comment
- **home/page.tsx**: `timeLabel` guards against null `startTime`/`endTime` values

---
id: 0148
title: "Feature — Meetings hub with Recall.ai integration"
status: archived
category: Added
release_date: 2026-04-01
source: CHANGELOG.md
---

## [2026-04-01] Feature — Meetings hub with Recall.ai integration

Full meetings feature across all platforms: calendar sync, Recall.ai bot recording, AI recaps, transcript Q&A, and second-brain integration.

### Backend (`apps/server`)

- **DB schema** (`schema.ts`): Added 4 tables — `meetIntegration`, `meeting`, `meetingMedia`, `meetingTranscript` with indexes.
- **Migration**: `0042_absurd_emma_frost.sql` generated.
- **Recall.ai client** (`lib/recall.ts`): `createRecallBot`, `getBotStatus`, `cancelBot`, `getBotTranscript` with retry logic.
- **Webhook** (`routes/recall-webhook.ts`): Handles `bot.status_change`, `recording.done`, `transcript.done` events.
- **tRPC meet router** (`trpc/routes/meet.ts`): `listMeetings`, `getMeeting`, `createMeeting`, `deleteMeeting`, `scheduleBot`, `cancelBot`, `generateSummary`, `askQuestion`, `syncFromCalendar`, `getIntegration`, `upsertIntegration`.
- **AI tools** (`routes/agent/tools.ts`): Added `listMeetings`, `getMeetingSummary`, `searchMeetingTranscript` tools for second-brain AI access.
- **Env** (`env.ts`): Added `RECALL_API_KEY`, `RECALL_API_BASE_URL`, `RECALL_WEBHOOK_SECRET`.
- **Types** (`types.ts`): Added `ListMeetings`, `GetMeetingSummary`, `SearchMeetingTranscript` to Tools enum.

### Web (`apps/mail`)

- **Routes** (`routes.ts`): Added `/mail/meetings` and `/mail/meetings/:meetingId`.
- **Navigation** (`config/navigation.ts`): Added "Meetings" with Video icon and `g + m` shortcut.
- **List page** (`meetings/page.tsx`): Time-grouped list, status filters, search, calendar sync button, empty state.
- **Detail page** (`meetings/[meetingId]/page.tsx`): Video player, AI recap, action items, transcript viewer, Q&A chat.

### macOS (`apps/macos`)

- **Navigation**: Added `.meetings` case to `MacPrimarySelection`, sidebar button, ⌘5 shortcut.
- **Service** (`Services/Meetings/MeetingsService.swift`): Full tRPC client for meetings CRUD + AI.
- **Views**: `MacMeetingsView.swift` (split list+detail), `MacMeetingDetailView.swift` (video, recap, transcript, Q&A).
- **Registration**: Added `meetingsService` to `MacAppServices`.

### iOS (`apps/ios`)

- **Navigation**: Added `.meetings` to `AppTab`, tab content in `MainTabView`.
- **Service** (`Services/Meetings/MeetingsService.swift`): Full tRPC client matching macOS.
- **Views**: `MeetingsListView.swift` (grouped list with search), `MeetingDetailView.swift` (video, recap, transcript, Q&A).
- **Registration**: Added `meetingsService` to `AppServices`.

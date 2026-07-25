---
id: 0054
title: "PRD rewrite + iOS feature implementation (Phases 1–6)"
status: archived
category: Added
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] PRD rewrite + iOS feature implementation (Phases 1–6)

### Documentation

- **PRD.md rewritten** as pure product spec — removed all architecture/code, added User Flows, Empty & Error States, Notifications, AI Interaction Model, Settings Screen Spec, Database Schema Revisions sections
- **AGENTS.md rewritten** from scratch — agent-agnostic architecture reference for all AI coding agents (Claude, Cursor, Gemini, etc.)
- **CLAUDE.md updated** — added iOS app detail (services layer, auth flows, data layer), fixed auth providers list
- **APPS_ARCHITECTURE.md updated** — fixed stale Expo/React Native and Next.js references

### iOS: Phase 1 — Empty & Error States

- New `CalendarPermissionView.swift` — shown when calendar access is denied/not-determined
- New `NetworkMonitor.swift` — NWPathMonitor wrapper with offline banner in MainTabView
- `AIChatView` — added AI unreachable error state with retry button
- `HomeView` — composite "Get Started" card when all sections empty

### iOS: Phase 2 — Settings Screen Completion

- **Delete account** — double confirmation (dialog → type "DELETE" alert), backend call + local wipe
- **Disconnect Gmail** — confirmation dialog, calls `connections.delete` tRPC
- **AI tone picker** — Professional/Casual/Concise preference injected into system prompt
- **Notification toggles** — in-app Task Due Reminders + Calendar Reminders toggles
- New API methods: `TodosAPIClient.deleteAccount()`, `TodosAPIClient.disconnectEmail()`

### iOS: Phase 3 — AI Context Awareness

- `AIChatView` suggestions now tab-aware (Home/Tasks/Email/Calendar each show relevant prompts)
- `AppServices.currentTab` tracks active tab, synced by MainTabView
- AI tone preference synced to `AIChatService.toneInstruction` and injected into system prompt

### iOS: Phase 4 — Session Handling

- `TodosAPIClient` now attempts silent refresh on 401 before marking session expired
- `AuthService.isSessionExpired` flag + `attemptSilentRefresh()` method
- Orange "Session expired — Sign in again" banner in MainTabView

### iOS: Phase 5 — Local Notifications

- New `NotificationService.swift` — UNUserNotificationCenter wrapper with TASK_REMINDER category
- Action buttons: Complete (marks task done) and Snooze 1h (reschedules)
- `TaskCaptureService` schedules/cancels notifications on task create/update/complete/delete
- `TodosApp.swift` — AppDelegate adapter for notification action handling

### iOS: Phase 6 — Database Schema Changes

- Added `emailThreadId` and `eventId` columns to task table in `schema.ts`
- Added indexes: `task_email_thread_id_idx`, `task_event_id_idx`
- Updated `TaskRecord.swift` with new optional properties
- Updated tRPC routes (create, update, sync) to accept and persist both fields

### Files Changed

- `PRD.md`, `AGENTS.md`, `CLAUDE.md`, `APPS_ARCHITECTURE.md`
- `apps/ios/Todus/Todus/App/AppServices.swift`
- `apps/ios/Todus/Todus/App/TodosApp.swift`
- `apps/ios/Todus/Todus/Data/Models/TaskRecord.swift`
- `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`
- `apps/ios/Todus/Todus/Features/Calendar/CalendarPermissionView.swift` (new)
- `apps/ios/Todus/Todus/Features/Home/HomeView.swift`
- `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
- `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`
- `apps/ios/Todus/Todus/Services/API/TodosAPIClient.swift`
- `apps/ios/Todus/Todus/Services/Auth/AuthService.swift`
- `apps/ios/Todus/Todus/Services/NetworkMonitor.swift` (new, from prior session)
- `apps/ios/Todus/Todus/Services/Notifications/NotificationService.swift` (new)
- `apps/ios/Todus/Todus/Services/Tasks/TaskCaptureService.swift`
- `apps/server/src/db/schema.ts`
- `apps/server/src/trpc/routes/tasks.ts`

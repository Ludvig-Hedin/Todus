---
id: 0125
title: "Medium severity — 46"
status: done
tags: [ios, bug-hunt, ux, code-review-backlog]
files: []
created: 2026-05-17
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-17 — iOS Bug-Hunt + UX-Polish Audit

## Medium severity — 46

_Closed by the 2026-06-13 backlog resolution pass (`CODE_REVIEW_BACKLOG.md` → "No open code defects remain": every code-defect item was fixed, built, tested and committed in passes 1-6). Re-open if this finding is still reproducible._


(Full per-surface lists archived in agent transcripts; high-leverage subset listed below)

### Email
- `EmailThreadView.swift:866` markAsRead failure poisons shared `errorMessage` → contaminates subsequent dismiss checks
- `EmailComposeView.swift:691-695` `canSend` blocks legitimate empty-subject replies
- `EmailRowView.swift:10-15` `timeString` cached in init → "Yesterday" stale across midnight
- `Services/Email/EmailService.swift:309-313` pagination dedupe by id only; stale page-1 thread retained when newer copy lands on page 2
- `EmailInboxView.swift:1269-1276` `consumePendingThreadNavigation` GCD asyncAfter fires after view disappears
- `EmailInboxView.swift:306-308` `badgeForciblyHidden` latches across refreshes
- `EmailComposeView.swift:94` Reply/ReplyAll separate autosave keys orphan drafts
- `EmailThreadView.swift:1786+` EmailHTMLView no nav delegate → in-place link nav strands user

### Tasks
- `Services/Reminders/AppleRemindersSyncService.swift:340-358` `inFlightUpserts` guard is no-op; redundant EKEventStore XPC calls
- `Services/Reminders/AppleRemindersSyncService.swift:340-357` Two-way sync never reopens — uncheck in Reminders, Todus stays done
- `Features/Tasks/InboxView.swift:128` `onChange(of: allTasks)` walks N items on every SwiftData mutation
- `Services/Tasks/TaskCaptureService.swift:98` `try? context.save()` swallows disk-full errors
- `Services/Tasks/TaskCaptureService.swift:65-66` No cap on `splitInputLines`; 10k-line paste = 10k enrichment tasks
- `Services/Reminders/AppleRemindersSyncService.swift:301-310` `pendingUpsertTaskIDs` retry recursive, no max-attempts

### Calendar
- `Features/Calendar/CalendarTimeGridView.swift:19, 67-69` `Timer.publish(...).autoconnect()` leaks per page in MultiDay
- `Features/Calendar/CalendarViewController.swift:140-172` `fetchEvents` ignores authorization revoke; stale events served forever
- `Features/Calendar/CalendarTabView.swift:483-485` `isLoading` not reset on Task cancellation
- `Features/Calendar/CalendarTabView.swift:204` `.highPriorityGesture(pinch)` conflicts with `UIPageViewController` swipe
- `Services/Meetings/MeetingsService.swift:140-146` `syncFromCalendar` only `print`s errors

### AI
- `Services/AI/AIChatService.swift:1107-1116, 2528-2534` Keep-alive deltas treated as `.unrecognised` → main-actor JSON decode spam
- `Services/AI/AIChatService.swift:2002-2007` 50-conversation history serialized into one Keychain blob → exceeds ~4KB item limit; silent persist failure
- `Services/AI/AIChatService.swift:1119-1132` Stale `streamFailed` not reset on cancel; retry banner from prior turn sticks
- `Services/AI/AIChatService.swift:1727-1734` `buildPayload` includes in-flight assistant placeholder content → duplicated assistant turn in next step
- `Services/AI/AIChatService.swift:346-393` `retry(...)` doesn't clear `messages[i].errorMessage` → footer pinned under successful response
- `Services/AI/AIChatService.swift:2070-2104` `fetchFullConversation` overwrites local renames/moves unconditionally

### Infra
- `Services/Subscription/SubscriptionService.swift:100-104` `cancel` re-entrancy on shared `isLoading`; spinner deadlock on double-tap
- `Services/Notifications/NotificationDigestService.swift:173-211` Hand-rolled URLSession bypasses TodosAPIClient — no 401 refresh, no superjson
- `Services/NetworkMonitor.swift:9, 16` `isConnected` defaults `true` pre-NWPath callback → wrong banner flash, false reconnect trigger
- `Services/Widgets/WidgetUpdateManager.swift:40-50` Tasks completed today without `dueDate` excluded from widget stats
- `Navigation/MainTabView.swift:86-101` Calendar permission desync — Settings flip without scenePhase change shows stale permission UI
- `Navigation/CreateSheet.swift:973-1011` Event create allows end < start; backend rejects, user loses transient state
- `DesignSystem/AppTheme.swift:14-17` Avatar cache `dataKey = urlString.hashValue` — non-stable across launches (process-salted), cross-user collision risk
- `DesignSystem/AppTheme.swift:36-48` Avatar JPEG bytes in UserDefaults → bloats prefs.plist, slows launch
- `DesignSystem/AppTheme.swift:530-543` `AppPrimaryButtonStyle` hardcodes `Color.blue` — ignores `Color.accentColor` / Increase Contrast

### Auth (additional)
- `AuthService.swift:228-358` Apple Sign In never sets `pendingAuthFlowExpiresAt` → provenance bypass + mid-flow URL kills state
- `App/RootView.swift:85-88, 105-108` `loadSharedAIProfile` called twice on signed-in launch
- `KeychainHelper.swift:38-43` Legacy-delete failure aborts save → silent token drop on locked keychain

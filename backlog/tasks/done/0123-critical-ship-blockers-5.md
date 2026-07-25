---
id: 0123
title: "Critical (ship-blockers) — 5"
status: done
tags: [ios, bug-hunt, ux, code-review-backlog]
files: []
created: 2026-05-17
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-17 — iOS Bug-Hunt + UX-Polish Audit

## Critical (ship-blockers) — 5

_Closed by the 2026-06-13 backlog resolution pass (`CODE_REVIEW_BACKLOG.md` → "No open code defects remain": every code-defect item was fixed, built, tested and committed in passes 1-6). Re-open if this finding is still reproducible._


| # | File:line | Title | Surface |
|---|-----------|-------|---------|
| C1 | `packages/swift-auth/Sources/TodusAuth/AuthService.swift:877-883` | Deep-link token injection on unauthenticated app — attacker `todus://auth-callback?token=X` accepted when signed out; Apple flow never sets `pendingAuthFlowExpiresAt` | auth |
| C2 | `apps/ios/Todus/Todus/App/TodosApp.swift:411-413` | Notification taps for email/AI/due-task/reminder are dead — switch only handles `TASK_COMPLETE`/`TASK_SNOOZE`, everything else falls into `default: break` | infra |
| C3 | `apps/ios/Todus/Todus/Services/AI/AIChatService.swift:1370-1485` + `Features/AI/AIChatView.swift:217-244` | Mutation confirmation deadlocks AI agent — `send_email`/`update_calendar_event`/`delete_calendar_event` suspend forever; no UI observes `pendingMutationConfirmation` | ai |
| C4 | `apps/ios/Todus/Todus/Services/AI/AIChatService.swift:416-434` | Mutation continuations leak on cancel — `cancelStream` only resumes delete continuations, never mutation ones; Stop mid-confirm leaks Task + CheckedContinuation warning | ai |
| C5 | `apps/ios/Todus/Todus/Features/Calendar/CalendarPermissionView.swift:39` | Calendar permission view stuck loading after grant — no `onReceive(.todusCalendarAuthorizationDidChange)`; view never invalidates | calendar |

---
id: 0126
title: "UX polish — top 20 across surfaces (84 total in agent transcripts)"
status: done
tags: [ios, bug-hunt, ux, code-review-backlog]
files: []
created: 2026-05-17
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-17 — iOS Bug-Hunt + UX-Polish Audit

## UX polish — top 20 across surfaces (84 total in agent transcripts)

_Closed by the 2026-06-13 backlog resolution pass (`CODE_REVIEW_BACKLOG.md` → "No open code defects remain": every code-defect item was fixed, built, tested and committed in passes 1-6). Re-open if this finding is still reproducible._


| # | Impact | File:line | Gap | Fix |
|---|--------|-----------|-----|-----|
| P1 | High | `Features/Email/EmailInboxView.swift:635-648` | Archive uses `role: .destructive` (red) — fear of mis-swipe | Drop `.destructive` |
| P2 | High | `Features/AI/AIChatView.swift:1332-1342` | Send button disappears when empty → layout shift | Always render, gate `.disabled(isEmpty)` |
| P3 | High | `Features/AI/AIChatView.swift:914-919` | "Thinking…" vanishes on first token but text may be empty for 10s if reasoning tokens stream | Keep indicator while `reasoningContent` grows + `content` empty |
| P4 | High | `Features/AI/AIChatView.swift:2247-2273` | Thumbs up/down is local-only no-op → fake feedback | Wire to feedback endpoint or remove |
| P5 | High | `Features/Tasks/TaskRowView.swift:286` | No haptic on complete | `UIImpactFeedbackGenerator(.light).impactOccurred()` |
| P6 | High | `Features/Tasks/TaskRowView.swift:112-117` | Context-menu Delete no confirmation (TaskTableView has one) | Add `confirmationDialog` |
| P7 | High | `Features/Calendar/CalendarTimeGridView.swift:155-160` | Event blocks <24pt below 44pt HIG touch target | `.frame(minHeight: 44)` on contentShape |
| P8 | High | `App/GmailOnboardingView.swift:51-84` | Skip stays tappable during connect → race | `.disabled(isConnecting)` |
| P9 | High | `Features/Email/EmailThreadView.swift:493-501` | Star button no accessibility state | `.accessibilityLabel(isStarred ? "Starred" : "Not starred")` |
| P10 | High | `Navigation/MainTabView.swift:296-308` | Offline banner subtle pill, no retry CTA | Add Retry button |
| P11 | High | `Features/Email/EmailComposeView.swift:201-231` | Send button no "Sending…" text, no success haptic | Add label + `.sensoryFeedback(.success, trigger:dismissed)` |
| P12 | High | `Features/Auth/AuthView.swift:144-165` | Apple/Google tappable while Email OTP loading | `.disabled(authService.isLoading)` on stage-1 stack |
| P13 | High | `Features/Auth/AuthView.swift:73-76` | Error banner persists indefinitely | Auto-clear via `.task(id: lastErrorMessage)` |
| P14 | High | `Features/Home/HomeView.swift:1054-1067` | No skeleton on cold launch — white 1-3s | 3 ghost rows while `\!hasLoadedEmailState` |
| P15 | High | `Features/Calendar/CalendarListView.swift:170-180` | Empty calendar dead-ends — no CTA | Add "Create event" button |
| P16 | Med | `Features/Tasks/BoardColumnView.swift:78-83` | Empty board column no `+` (drop-only on touch) | Add `+` to column header |
| P17 | Med | `Features/Calendar/CalendarEventBlockView.swift:18-48` | No VoiceOver label | `.accessibilityLabel("\(title), \(timeString)")` |
| P18 | Med | `App/NotificationsOnboardingView.swift:90-99` | Skip tappable during permission request | `.disabled(isRequesting)` |
| P19 | Med | `Features/AI/AIChatService.swift:1521` | `appendFallback` writes literal "Done." | Generate from chip set |
| P20 | Med | `Features/Email/EmailThreadView.swift:1564` | Timestamp uses abbreviated date for recent — "2 min ago" expected | `RelativeDateTimeFormatter` <24h |

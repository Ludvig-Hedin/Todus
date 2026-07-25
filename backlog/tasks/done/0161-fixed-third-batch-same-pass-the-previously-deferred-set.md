---
id: 0161
title: "Fixed — third batch (same pass; the previously-\"deferred\" set)"
status: done
tags: [code-review-backlog]
files: [components/tasks/task-item.tsx, lib/server-tool.ts, voice-provider.tsx, **/dev.log]
created: 2026-06-13
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Backlog resolution pass — 2026-06-13 (whole-repo)

## Fixed — third batch (same pass; the previously-"deferred" set)

All build-verified (iOS + macOS green, 94 iOS tests pass; server/web tsc-clean on touched files).
- **iOS EM-1 + EM-3** — `SenderAvatarView` now renders through a downsampling, disk-cached loader (`AvatarImageLoader`: NSCache → `AvatarDiskCache` → fetch+ImageIO thumbnail at point-size×scale → persist), replacing raw `AsyncImage`; waterfall + person-vs-brand treatment preserved.
- **iOS EM-7** — inbox search uses a precomputed per-thread lowercased blob (no per-keystroke 4-field lowercasing); `threadsForSender` cached in `@State`; sender-group rebuild already gated to People view.
- **iOS H9** — Day view now renders the unified Apple+Google+CalDAV events via a single-column `CalendarMultiDayView(dayCount:1)` (same renderer as Multi-Day); removed the "switch to Multi-Day" banner.
- **Server B-025** — `GENERATIVE_UI_PROMPT` gated behind `supportsGenerativeUI` request flag (default true; `AiChatPrompt` takes `generativeUI` option).
- **Server B-028** — added `autoLabelThreads` policy field (default true); `labelGenerationWorkflow` registration gated by it (vectorization intentionally always-on).
- **Server B-015 (cache)** — added a module-level in-memory isolate cache (~24h TTL, 2000-cap) around `resolveSenderAvatar` (no general KV binding exists; this covers repeat hits within an isolate).
- **Server + clients — subscription productId** — `subscription.getStatus` now returns the active `productId`+`interval` (sourced from Autumn); macOS cancel uses the real product instead of hardcoded `pro_monthly`.
- **Server + web — PAR-A2** — `createEvent`/`updateEvent`/`deleteEvent` accept an optional user-scoped `connectionId` (act on a non-active connection's calendar); added `calendarsMulti` (calendars across all google connections); web `EventEditDialog` create mode has a calendar picker.
- **macOS reminder scheduling** — `MacNotificationService` reminders are now actually scheduled: `reconcileTaskReminders` runs on launch / foreground / toggle (auth requested), schedules per-task `UNCalendarNotificationTrigger`s + the due-today digest, cancels orphans. (`calendarRemindersEnabled` has no scheduler defined on either platform — left out of scope.)
- **macOS move-to-folder** — "Move to…" context-menu submenu in inbox + thread; `EmailService.move(ids:toLabelId:fromFolder:)` via `mail.modifyLabels` with optimistic apply + rollback.
- **macOS notification cold-launch** — taps during cold launch are queued (`pendingNotificationResponses`) and replayed in `initializeApp()`, mirroring `pendingDeepLinks`.
- **macOS event-edit prefill** — `CalendarEvent` carries `location`/`notes`; edit sheet seeds + round-trips them through `CalendarService.updateEvent`/`createEvent`.
- **macOS BH-0601-2** — foreground thread-open joining a prefetch now sets a fallback `errorMessage` on nil result.
- **macOS BH-0601-3** — `CalendarEvent.id` is the composite namespaced id (collision-free Identifiable); `providerEventId` used for EKEventStore lookups.
- **Web 001** — extracted `TaskItemCompact` into `components/tasks/task-item.tsx`; home page imports it (removed the inline duplicate).
- **Web PAR-F1** — removed the dead `/forgot-password` link from the commented login block (route actually exists; the dead reference is gone).
- **Web PAR-C (code)** — voice client-tool bridge is code-complete + compiling: `lib/server-tool.ts` `callServerTool` → `POST /api/ai/do/:action`; `voice-provider.tsx` `clientTools` re-enabled, errors caught (no throw on a normal session). The code-review finding ("clientTools commented out + broken `@/lib/server-tool` import") is resolved. (Its runtime activation is a deployment/operator prerequisite, not a code defect — see the operator-prerequisites note below.)
- **Hygiene** — added `**/dev.log` to root `.gitignore` (B-050).

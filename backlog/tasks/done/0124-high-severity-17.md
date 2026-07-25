---
id: 0124
title: "High severity — 17"
status: done
tags: [ios, bug-hunt, ux, code-review-backlog]
files: []
created: 2026-05-17
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-17 — iOS Bug-Hunt + UX-Polish Audit

## High severity — 17

_Closed by the 2026-06-13 backlog resolution pass (`CODE_REVIEW_BACKLOG.md` → "No open code defects remain": every code-defect item was fixed, built, tested and committed in passes 1-6). Re-open if this finding is still reproducible._


### Auth (2)
- **H1** `AuthService.swift:1354-1372` — Stale refresh token persisted across re-login; JWT-only third branch never clears `refreshToken`/`currentSessionId` → cross-account session leak
- **H2** `Services/Auth/AuthSessionStore.swift:294-305` + `TodosApp.swift:42,54` — Legacy Supabase store flipped into magic-link state by Better Auth callback URLs containing `email=`

### Email (3)
- **H3** `Features/Email/EmailThreadView.swift:493-501` — Star toggle never rolls back on API failure; user thinks starred, isn't
- **H4** `Features/Email/EmailThreadView.swift:1049-1054` — `markAsSpam` always dismisses regardless of success; offline spam-report silently fails
- **H5** `Features/Email/EmailThreadView.swift:294-321` + `EmailInboxView.swift:600-612` — `priorError \!= current` failure detection fragile across shared singleton state; concurrent ops mask/mimic failures

### Tasks (3)
- **H6** `Features/Tasks/TasksTabView.swift:209-220` — `consumePendingTaskNavigation` uses GCD `asyncAfter` w/ no cancel; rapid second tap shows stale task
- **H7** `Services/Parsing/RemoteFirstTaskParsingService.swift:38-55` — Remote NLP `lowConfidence` silently dropped; only surfaces on local fallback
- **H8** `Services/Tasks/TaskCaptureService.swift:100-129` — Capture rollback races concurrent enrichment enqueues; non-deterministic state machine

### Calendar (3)
- **H9** `Features/Calendar/CalendarTabView.swift:448, 456` — Day view shows ONLY Apple events; Google events stripped because `loadEvents` early-returns for `.day` mode
- **H10** `Features/Calendar/CalendarTabView.swift:520-524` — Tapping Google/CalDAV event silently no-ops; `event(withIdentifier:)` returns nil and code `return`s
- **H11** `Features/Calendar/EKWrapper.swift:46-50` — Force-unwrap on `ekEvent.calendar.cgColor` crashes when calendar deleted mid-session

### AI (3)
- **H12** `Services/AI/AIChatService.swift:1910-1929` — `flushTokenBuffer` runs against stale messageID; mid-flush `clearHistory`/`retry` loses tokens
- **H13** `Services/AI/AIChatService.swift:2192-2196` — Calendar snapshot leaks "not granted" string after permission grant until cache invalidated
- **H14** `Services/AI/AIChatService.swift:1066-1078` — SSE byte parser splits on `\n` only; `\r\n` from CDN causes `"[DONE]\r"` mismatch + decode failures on final chunk

### Infra (3)
- **H15** `Services/API/TodosAPIClient.swift:163-189` — TRPC body sent as raw JSON; server superjson expects `{json,meta}` for `Date`/`Set`/`BigInt` — dates corrupt over wire
- **H16** `Services/API/TodosAPIClient.swift:60-64` — `JSONSerialization.data(withJSONObject:)` crashes on String/Int inputs (fragment rule); `trpcBatchQuery` with id arrays raises NSInvalidArgumentException
- **H17** `Services/Voice/AudioPlayerManager.swift:68-82` — `ensureEngineRunning` re-attaches already-attached node when session ends without `stop()`; crashes on reconnect

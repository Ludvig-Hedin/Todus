---
id: 0172
title: "Fixed this pass (7)"
status: done
tags: [macos, qa, code-review-backlog]
files: [Services/Email/EmailService.swift, Services/API/TodosAPIClient.swift, Domain/EmailModels.swift, Views/Email/MacEmailThreadView.swift, Views/Email/MacEmailInboxView.swift]
created: 2026-06-13
source: CODE_REVIEW_BACKLOG.md
---

> Source context: macOS QA pass — 2026-06-13 — email loading / thread-open / hangs

## Fixed this pass (7)

| File | Sev | What changed |
|------|-----|--------------|
| `Services/Email/EmailService.swift` `checkConnection` | 🔴 blocker | Any transient failure (timeout/offline/5xx) set `hasConnection=false`, parking **connected** users on the "Connect Gmail" onboarding prompt. Now only a *successful* empty response sets it false; failures set `connectionCheckFailed` and leave a known-good connection intact. New `connectionCheckFailedState` view shows a retry instead of the connect prompt. |
| `Services/Email/EmailService.swift` `loadThreads` (401 catch) | 🟠 high | A 401 set `hasConnection=false` (→ wrong "Connect Gmail" state) and left `errorMessage` nil (silent). Now surfaces "Your session expired" and leaves connection state alone; root view drives re-auth via `isSessionExpired`. |
| `Services/API/TodosAPIClient.swift` retry loop | 🟡 med | Added `try Task.checkCancellation()` at the top of the retry loop so a cancelled/timed-out request stops promptly instead of burning another attempt + full URLSession timeout. `loadThreads` now distinguishes timeout copy and treats `CancellationError` as non-error. |
| `Domain/EmailModels.swift` `EmailSender`/`EmailMessage` | 🟠 high | **The "errors entering threads" cause.** A message with null/missing `sender` or null `email` threw a `DecodingError` that aborted the *whole* `mail.get` thread decode → hard error screen. Email decode is now tolerant (`email` → `""`, missing sender → "Unknown sender" placeholder). |
| `Services/Email/EmailService.swift` `GetThreadResponse` | 🟠 high | Messages now decode element-by-element via `FailableDecodable<EmailMessage>`, so one malformed message (e.g. missing `id`) is dropped instead of sinking the entire thread. |
| `Views/Email/MacEmailThreadView.swift` `recomputeFallbackChips` + `loadThread` | 🟡 med | The verification/tracking regex ran a full-document `<[^>]+>` strip on the main actor at thread-open (stutter on large newsletters). Input now capped to 20k chars. `markAsRead` gated on a successful load (no longer marks read on failed/cancelled opens). |
| `Views/Email/MacEmailInboxView.swift` paginator | 🟡 med | A failed "load more" set an (invisible) error and left the cursor, so `.onAppear` re-fired immediately → tight retry loop hammering the backend. Added `paginationFailed` flag + an explicit "Couldn't load more — Retry" footer; auto-fire is gated on the flag. |

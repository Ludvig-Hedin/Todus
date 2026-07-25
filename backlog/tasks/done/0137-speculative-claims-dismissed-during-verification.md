---
id: 0137
title: "Speculative claims dismissed during verification"
status: done
tags: [ios, bug-hunt, code-review-backlog]
files: []
created: 2026-05-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-20 — iOS Mobile App Bug Hunt

## Speculative claims dismissed during verification

(Listed so the next bug hunt doesn't re-flag them.)

- ~~`AuthView.swift:142` — `if case .otpPending(let email)` pattern allegedly broken.~~ Verified valid Swift; `otpPendingEmail` works correctly.
- ~~`TodosAPIClient.swift:231` — TRPC envelope decode `try?` "swallows" errors.~~ Documented intentional fallback to bare-response decoding (see comment at line 239).
- ~~`TodosAPIClient.swift:345` — bearer token nil header.~~ Code already uses `if let token` guard; header only set when token exists.
- ~~`TodosAPIClient.swift:376–383` — 401 retry "broken".~~ `didRefresh` flag intentionally limits refresh to one attempt per request, then surfaces `unauthorized`. Behaviour matches the inline comment.
- ~~`TodosAPIClient.swift:404–413` — mutation retries unsafe.~~ Retry list is explicitly restricted to URLErrors that mean "request did not reach the server"; matches the inline comment.
- ~~`CalendarService.swift:96–124` — empty `hiddenCalendarIds` "returns everything".~~ Documented as legacy behaviour in the doc comment ("An empty set fetches across all calendars").
- ~~`UnifiedCalendarService.swift:82–93` — Apple/Google tasks "throw and silently lose Apple data".~~ Neither helper is `throws`; the `async let` returns `[]` on failure.
- ~~`EmailInboxView.swift:627` — pagination success misdetected as failure.~~ Logic correctly checks `if let current` *and* `current \!= priorError`; nil case is handled.

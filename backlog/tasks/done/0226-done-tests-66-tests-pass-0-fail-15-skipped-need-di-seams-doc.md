---
id: 0226
title: "DONE Tests — 66 tests pass, 0 fail, 15 skipped (need DI seams, documented per-test)."
status: done
tags: [task-md, sprint]
files: []
created: 2026-05-17
source: TASK.md
---

> Source context: TASK.md → Current iOS Parity + Hardening Sprint (2026-05-17)

- `DONE` **Tests** — 66 tests pass, 0 fail, 15 skipped (need DI seams, documented per-test). 8 new test files:
  - `AuthServiceTests` (12 tests, 9 active) — C1 deep-link rejection, `preloadTokens` determinism, init→auth transition, token preview safety.
  - `TodosAPIClientTests` (8 tests, 6 active) — superjson Date-meta envelope, omitted-meta plain payload, nested-date dotted path, batch wrap with String/Int (H16 regression pin).
  - `AIChatServiceTests` (12 tests, 11 active) — CRLF / LF-only classify, `[DONE]` with/without trailing CR (H14 pin), heartbeat skip, chunk-boundary residual, replay end-to-end, malformed-JSON tolerance.
  - `EmailServiceTests`, `AppleRemindersSyncServiceTests`, `NetworkMonitorTests`, `AppThemeAvatarCacheTests`, `RemoteFirstTaskParsingServiceTests`.
  - `TodosUITests` target stood up (xcodegen). Smoke test `app.launch()` + window-exists assertion. Manual follow-up: implement `--ui-testing` launch-arg stub in `AppServices` for deeper E2E.

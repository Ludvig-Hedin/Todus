---
id: 0212
title: "Allowlisted account required for all three platforms."
status: done
tags: [task-md, sprint]
files: []
created: 2026-05-24
source: TASK.md
---

> Source context: TASK.md → Task 16 — Design System screenshot regression suite (2026-05-24) — IN PROGRESS (infra DONE)

- **Allowlisted account required for all three platforms.** The DS viewers are gated by `TodusDeveloperAccess.isAllowlisted` (Swift) / `isAllowlisted` (web). There is no fake-account mock yet, so:
  - **Web**: capture needs `PLAYWRIGHT_SESSION_TOKEN` / `PLAYWRIGHT_SESSION_DATA` env vars from a live signed-in session.
  - **iOS**: the simulator must already have an allowlisted account signed in (the auth path through Apple/Google deep-link is real network; can't be mocked in-process from a capture script).
  - **macOS**: same — the native app needs to be signed in.

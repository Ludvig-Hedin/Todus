---
id: 0270
title: "DONE Developer mode in Settings (2026-04): Allowlisted email (TodusDeveloperAccess via TODUSALLOWLIS"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → macOS UI

- `DONE` **Developer mode in Settings (2026-04):** Allowlisted email (`TodusDeveloperAccess` via `TODUS_ALLOWLISTED_EMAILS` env, comma-separated) sees a **Developer Mode** toggle; **Auth Debug** appears only when the toggle is on. Persisted as `TaskApp.developerModeEnabled` (same as iOS). Swift-auth `TodusDeveloperAccess` + `TodusHTTPClient` are included in the macOS target compile sources so `import TodusAuth` is not required for the single-module app build.

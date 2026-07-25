---
id: 0214
title: "iOS auto path is blocked by missing deep-link router."
status: done
tags: [task-md, sprint]
files: [TodosApp.swift]
created: 2026-05-24
source: TASK.md
---

> Source context: TASK.md → Task 16 — Design System screenshot regression suite (2026-05-24) — IN PROGRESS (infra DONE)

- **iOS auto path is blocked by missing deep-link router.** The `--auto` script skips DS slugs cleanly; until `TodosApp.swift` `.onOpenURL` learns to route `todus://settings/<name>` we have to use `pnpm parity:screenshots:capture:ios -- --surface design-system` (interactive). Quickest unblock is ~30 LOC in `TodosApp.swift` to set `services.navigateTo = .settings` + a pending settings route enum.

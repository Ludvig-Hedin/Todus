---
id: 0213
title: "macOS sidebar section-by-section is interactive."
status: done
tags: [task-md, sprint]
files: []
created: 2026-05-24
source: TASK.md
---

> Source context: TASK.md → Task 16 — Design System screenshot regression suite (2026-05-24) — IN PROGRESS (infra DONE)

- **macOS sidebar section-by-section is interactive.** The DS sheet uses a SwiftUI `selection` binding with no AppleScript hook to set it programmatically. Operator runs `pnpm parity:screenshots:capture:macos:auto -- --surface design-system --interactive` and clicks each tab between captures.

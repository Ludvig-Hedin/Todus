---
id: 0215
title: "No automated pixel-diff yet."
status: done
tags: [task-md, sprint]
files: [check-screenshots.mjs]
created: 2026-05-24
source: TASK.md
---

> Source context: TASK.md → Task 16 — Design System screenshot regression suite (2026-05-24) — IN PROGRESS (infra DONE)

- **No automated pixel-diff yet.** `check-screenshots.mjs` is presence-only. Suggested next step: wire `pixelmatch` or `odiff` for visual regression on the DS slugs specifically (low-risk because that surface is read-only by design — content shouldn't change unless tokens move).

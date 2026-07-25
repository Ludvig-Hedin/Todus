---
id: 0250
title: "DONE Native AI chat timeout / \"Connection lost\" investigation (2026-04): /api/ai/chat now opens the"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → Current Native Fix Batch

- `DONE` **Native AI chat timeout / "Connection lost" investigation (2026-04):** `/api/ai/chat` now opens the SSE response immediately instead of blocking on the upstream provider handshake, emits a bootstrap event so iOS receives bytes right away, and returns explicit SSE `error` events if OpenRouter/Gemini fails before content starts. iOS also now uses a 180s stream timeout for chat requests so long tool-planning turns do not trip the default request timer.

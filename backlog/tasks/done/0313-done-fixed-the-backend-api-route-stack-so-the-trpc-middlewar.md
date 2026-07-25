---
id: 0313
title: "DONE Fixed the backend /api route stack so the tRPC middleware no longer intercepts sibling /api/ai/"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → Current Web/Server Fix Batch

- `DONE` Fixed the backend `/api` route stack so the tRPC middleware no longer intercepts sibling `/api/ai/*` routes; this restores the iOS live voice-chat WebSocket proxy at `/api/ai/voice-ws`.

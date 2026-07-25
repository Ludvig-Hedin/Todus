---
id: 0310
title: "DONE AI chat tool-only response fix: AI chat now responds when the model emits only toolcalls (e.g."
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → Current Web/Server Fix Batch

- `DONE` AI chat tool-only response fix: AI chat now responds when the model emits only `tool_calls` (e.g. "create a reminder"). `SSEToolCall` deltas accumulate across fragments by `index`, the streaming pass is wrapped in a multi-step agent loop that sends tool results back to the model, and a "Done." fallback prevents empty bubbles. Server `chatMessageSchema` uses `passthrough` and accepts `tool_calls` / `tool_call_id` / `name`. iOS + macOS now also expose `update_calendar_event` / `delete_calendar_event` tools.

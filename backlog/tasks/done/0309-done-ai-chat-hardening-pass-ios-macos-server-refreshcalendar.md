---
id: 0309
title: "DONE AI chat hardening pass (iOS + macOS + server): refreshCalendarSnapshot on macOS now embeds even"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → Current Web/Server Fix Batch

- `DONE` AI chat hardening pass (iOS + macOS + server): `refreshCalendarSnapshot` on macOS now embeds event identifiers so `update_calendar_event` / `delete_calendar_event` are actually reachable; server skips mention enrichment, web-search heuristics, and attachment merging on follow-up tool steps; clients drop `attachments`/`mentions` from follow-up payloads; `assistant_with_tool_calls` content is `nil` (not empty string) so providers don't reject the message; voice tool guards (`create/update/delete_calendar_event`, `send_email`) now use a per-condition guard chain matching text chat. Debug builds verified on both targets.

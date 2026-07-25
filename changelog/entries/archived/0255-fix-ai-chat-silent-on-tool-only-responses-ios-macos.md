---
id: 0255
title: "Fix — AI chat silent on tool-only responses (iOS + macOS)"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Fix — AI chat silent on tool-only responses (iOS + macOS)

- [Fix] AI chat ("Ain") now responds correctly when the model emits only `tool_calls` in its first SSE round (e.g. "create a reminder", "schedule a meeting"). Previously the assistant bubble was empty because (a) fragmented `tool_calls` deltas were rejected by a strict SSE schema, and (b) tool results were never sent back to the model for a natural-language confirmation.
- [Fix] `SSEToolCall` fields (`index`, `id`, `function`) are now optional and accumulated across deltas keyed by `index`, matching the OpenAI streaming protocol.
- [Fix] Streaming is wrapped in a multi-step agent loop (max 5 iterations): if a step returns tool calls, they are executed and the results are appended as `tool` role messages plus an `assistant_with_tool_calls` message before re-calling the model. The model then produces user-visible confirmation text.
- [Fix] If the loop completes without any visible content, a fallback "Done." message is appended so the bubble is never empty.
- [Fix] Server `chatMessageSchema` uses `.passthrough()` and explicitly accepts `tool_calls`, `tool_call_id`, and `name` so the multi-step protocol can round-trip through OpenRouter without zod stripping fields.
- [Feature] iOS + macOS chat now declares `update_calendar_event` and `delete_calendar_event` tools alongside `create_calendar_event`, and includes execution handlers backed by `CalendarService.updateEvent` / `deleteEvent`.
- **Files:** `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`, `apps/macos/TodusMac/Services/AI/MacAIChatService.swift`, `apps/server/src/routes/ai.ts`

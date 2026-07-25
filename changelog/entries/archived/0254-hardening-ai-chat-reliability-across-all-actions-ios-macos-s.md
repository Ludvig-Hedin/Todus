---
id: 0254
title: "Hardening — AI chat reliability across all actions (iOS + macOS + server)"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Hardening — AI chat reliability across all actions (iOS + macOS + server)

- [Fix] **macOS calendar update/delete were unreachable from chat.** `refreshCalendarSnapshot` now embeds each event's identifier as `[<id>]` next to the title and tells the model to pass it back as `id` to `update_calendar_event` / `delete_calendar_event`. Without this the model had no handle to target an existing event.
- [Fix] **Follow-up tool steps no longer waste resources or confuse providers.** When iOS/macOS re-call `/api/ai/chat` with `tool` role messages from the previous step, the server now skips mention enrichment, web-search heuristics, and attachment merging (those only apply to the original user turn). The clients also drop `attachments` and `mentions` from follow-up payloads.
- [Fix] **`assistant_with_tool_calls` content normalization.** iOS and macOS now send `content: nil` (omitted) instead of `content: ""` when an assistant message exists only to carry tool calls. Some providers reject empty-string content paired with `tool_calls`, which manifested as silent failures mid-loop.
- [Fix] **Voice tool guards no longer conflate failure modes.** `create_calendar_event`, `update_calendar_event`, `delete_calendar_event`, and `send_email` in the voice tool path now use a per-condition guard chain (permission → args decode → ISO date parse → service availability → execute) matching the text-chat path, so users get a precise error instead of a generic "couldn't do that".
- **Files:** `apps/server/src/routes/ai.ts`, `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`, `apps/macos/TodusMac/Services/AI/MacAIChatService.swift`
- **Verified:** Debug builds pass on both iOS and macOS targets.

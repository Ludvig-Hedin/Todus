---
id: 0244
title: "DONE macOS voice MVP — global hotkey, state machine, tool calling, Mem0 ingest (2026-05-10): ⌘⇧Space"
status: done
tags: [task-md, sprint]
files: []
created: 2026-05-10
source: TASK.md
---

> Source context: TASK.md → Current Voice Assistant Phase 1 (macOS)

- `DONE` **macOS voice MVP — global hotkey, state machine, tool calling, Mem0 ingest (2026-05-10):** `⌘⇧Space` push-to-talk runs end-to-end via the `VoiceSessionCoordinator` against the existing `/api/ai/voice-ws` Gemini Live proxy. Tools (`create_task`, `update_task`, `delete_task`, `get_time`) execute through `MacAIChatService.executeVoiceTool` and a Pi-portable `VoiceToolExecutor` seam. Voice transcripts persist via `ai.saveConversation` and ingest into Mem0 on save. New `GET /api/ai/voice/system-prompt` route centralizes the persona + AI profile + memories. Wake word ships as a fail-soft stub for Phase 1.5 Porcupine integration. Build green: `xcodebuild -project apps/macos/TodusMac.xcodeproj -scheme TodusMac` + `pnpm exec tsc --noEmit` (pre-existing TS noise outside voice files). User enables via Settings → Voice Assistant — both switches default OFF.

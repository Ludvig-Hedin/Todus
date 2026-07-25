---
id: 0253
title: "DONE Native live voice chat moved to Gemini 3.1 Flash Live (2026-04): iOS + macOS VoiceSessionConfig"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → Current Native Fix Batch

- `DONE` **Native live voice chat moved to Gemini 3.1 Flash Live (2026-04):** iOS + macOS `VoiceSessionConfig.geminiDefault()` now use `gemini-3.1-flash-live-preview` instead of the rejected `models/gemini-2.0-flash-live-001` string, and the live-voice headers now surface the runtime model name as **Gemini 3.1 flash live**. Both native `GeminiLiveProvider.sendText` paths were also migrated from `clientContent` to `realtimeInput.text` to match the current Gemini Live API contract for in-session text.

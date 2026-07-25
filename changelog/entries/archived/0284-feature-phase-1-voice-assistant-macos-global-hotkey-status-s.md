---
id: 0284
title: "Feature — Phase 1 voice assistant (macOS): global hotkey, status state machine, voice tools, Mem0 ingest"
status: archived
category: Added
release_date: 2026-05-10
source: CHANGELOG.md
---

## [2026-05-10] Feature — Phase 1 voice assistant (macOS): global hotkey, status state machine, voice tools, Mem0 ingest

- [Feature] **Backend `GET /api/ai/voice/system-prompt`** ([`apps/server/src/routes/ai.ts`](apps/server/src/routes/ai.ts)) — Bearer-auth route returns one composed system instruction (Todus voice persona + AI profile + Mem0 memories) ready to drop into Gemini Live's `setup.systemInstruction`. Reuses `getCachedMemories`, `formatMemoriesForPrompt`, `getSharedAIProfilePromptForUser` so voice and text chat share context. Failures fall back to a default persona — voice never breaks if Mem0 is down.
- [Feature] **`ai.saveConversation` ingests voice transcripts into Mem0** ([`apps/server/src/trpc/routes/ai/conversations.ts`](apps/server/src/trpc/routes/ai/conversations.ts)). Previously only `/api/ai/chat` wrote to Mem0; voice never went through that route, so "remember X" said over voice was lost. Now the most-recent user/assistant pair is fire-and-forget posted to Mem0 on every save, cache invalidated + preloaded so the next session sees the memory immediately.
- [Feature] **macOS voice services (`apps/macos/TodusMac/Services/Voice/`)**:
  - `VoiceSystemPromptClient.swift` — fetches the system prompt with 60s cache + offline fallback persona.
  - `VoiceToolRegistry.swift` — Gemini function declarations (`create_task`, `update_task`, `delete_task`, `get_time`) + `VoiceToolExecutor` protocol (Pi-portable seam).
  - `MacAIChatService.executeVoiceTool` — runs the same SwiftData mutations the text-chat tools use, returns Gemini-shaped JSON.
  - `AudioInputBroker.swift` — single-tap AVAudioEngine fan-out so wake-word + Live can share frames without crashing the engine.
  - `HotkeyService.swift` — global ⌘⇧Space push-to-talk via Carbon `RegisterEventHotKey` (works inside App Sandbox without Input Monitoring permission).
  - `WakeWordService.swift` — Phase 1 stub fail-softing as `[Wake] disabled — hotkey only`. Phase 1.5 plugs in Picovoice Porcupine with the built-in `"computer"` keyword.
  - `VoiceSessionCoordinator.swift` — `@Observable` state machine (`idle`, `wakeListening`, `triggered`, `recording`, `thinking`, `speaking`, `toolRunning`, `interrupted`, `error`, `sleeping`) with logged transitions, transcript persistence via `ai.saveConversation`, and tool dispatch.
  - `VoiceStatusWindow.swift` — floating status panel with state pill + live transcript + last tool call.
- [Feature] **Settings → Voice Assistant** ([`MacSettingsView.swift`](apps/macos/TodusMac/Views/Settings/MacSettingsView.swift)) — master toggle ("Press ⌘⇧Space to talk to Todus") and always-listening toggle. Both default OFF — the always-on mic is opt-in.
- [Feature] **`MacAppServices.applyVoiceAssistantState`** drives the coordinator from saved prefs so toggling Settings registers/unregisters the hotkey live. The chat panel temporarily yields the mic and re-arms the global loop on close.
- [Files] `apps/server/src/routes/ai.ts`, `apps/server/src/trpc/routes/ai/conversations.ts`, `apps/macos/TodusMac/Services/Voice/VoiceSystemPromptClient.swift`, `apps/macos/TodusMac/Services/Voice/VoiceToolRegistry.swift`, `apps/macos/TodusMac/Services/Voice/AudioInputBroker.swift`, `apps/macos/TodusMac/Services/Voice/HotkeyService.swift`, `apps/macos/TodusMac/Services/Voice/WakeWordService.swift`, `apps/macos/TodusMac/Services/Voice/VoiceSessionCoordinator.swift`, `apps/macos/TodusMac/Views/Voice/VoiceStatusWindow.swift`, `apps/macos/TodusMac/Services/AI/MacAIChatService.swift`, `apps/macos/TodusMac/App/MacAppServices.swift`, `apps/macos/TodusMac/App/TodusMacApp.swift`, `apps/macos/TodusMac/Views/Voice/MacVoiceChatPanel.swift`, `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift`, `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`, `docs/voice/PHASE_1.md`, `CHANGELOG.md`, `TASK.md`

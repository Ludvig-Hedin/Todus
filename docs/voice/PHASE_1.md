# Todus Voice Assistant — Phase 1 (macOS)

> Status: shipped 2026-05-10. macOS only. Phase 1.5 = Porcupine wake word. Phase 2 = Pi voice daemon.

## What Phase 1 ships

- **Global push-to-talk** — `⌘⇧Space` from anywhere on the system. Hold to record, release to let the model speak.
- **Voice tools** — `create_task`, `update_task`, `delete_task`, `get_time`. Routed through the same SwiftData mutations the text chat uses (no parallel implementation).
- **Server-rendered system prompt** — single `GET /api/ai/voice/system-prompt` returns persona + AI profile + Mem0 memories. Used as Gemini Live `setup.systemInstruction`.
- **Voice transcripts hit Mem0** — every voice session saves an `aiConversation` row, and `ai.saveConversation` now fires-and-forgets the latest user/assistant pair to Mem0. `"remember X"` said over voice persists for the next session.
- **State machine + status window** — `idle → wakeListening → triggered → recording → thinking → speaking → toolRunning(name) → interrupted → error → sleeping`. Logged to `app.log` on every transition.
- **Settings → Voice Assistant** — master toggle + always-listening toggle, both default OFF.

## What Phase 1 does NOT ship

- **Wake word** — `WakeWordService.swift` is a fail-soft stub. Real detection (Picovoice Porcupine, built-in `"computer"` keyword) lands in Phase 1.5.
- **Custom "Hey Todus" wake word** — Phase 2.
- **Clap detection** — Phase 2.
- **Menu bar item** — Phase 1.5.
- **Sleep-after-N-seconds auto-disconnect** — coordinator state exists, timer not wired.
- **Calendar / email / web-search voice tools** — Phase 2 (LLM can already do these via the chat panel).
- **iOS voice changes** — already separate; Phase 1 only touches macOS.
- **Pi voice daemon** — Phase 2 sibling package, will reuse the same `/api/ai/voice/system-prompt` + `/api/ai/voice-ws` + `ai.saveConversation` contracts.

## How to enable

1. Run the app: `pnpm macos`.
2. Settings → Voice Assistant → toggle **Voice assistant** ON.
3. (Optional) toggle **Always-listening (wake word)** ON — Phase 1 logs `[Wake] disabled — hotkey only` and continues.
4. Press and hold `⌘⇧Space`. Speak. Release. The status window pops up showing the live transcript and state.
5. Disconnect via the End button on the status window or by pressing `⌘⇧Space` again to start a new session.

First launch will request microphone access. The Carbon `RegisterEventHotKey` API does NOT need Input Monitoring permission, so the only privacy prompt is the standard mic dialog.

## Architecture

```
   ┌─────────────────────────────────┐
   │  ⌘⇧Space  HotkeyService          │  registers via Carbon RegisterEventHotKey
   │  (future) WakeWordService        │  shares 16kHz Int16 frames via AudioInputBroker
   └────────────────┬─────────────────┘
                    │ trigger
                    ▼
   ┌─────────────────────────────────┐         ┌──────────────────────┐
   │  VoiceSessionCoordinator         │  fetch  │  /api/ai/voice/      │
   │  - state machine                 │ ──────▶│  system-prompt       │
   │  - audio fan-out via broker      │         │  (persona + Mem0)    │
   │  - transcript persistence        │         └──────────────────────┘
   └────────────────┬─────────────────┘
                    │ wss://…/api/ai/voice-ws
                    ▼
   ┌─────────────────────────────────┐
   │  GeminiLiveProvider              │  ←→  Gemini Live (BidiGenerateContent)
   │  - WebSocket transport           │
   │  - tool call routing             │
   └────────────────┬─────────────────┘
                    │ toolCall
                    ▼
   ┌─────────────────────────────────┐
   │  VoiceToolRegistry               │  ─── get_time → local
   │   ↓ via VoiceToolExecutor protocol
   │  MacVoiceToolExecutor            │  ─── create_task / update_task / delete_task
   │   ↓                              │       → MacAIChatService.executeVoiceTool
   │  MacAIChatService                │       → SwiftData (TaskRecord)
   └─────────────────────────────────┘
                    │
   on disconnect    │
                    ▼
   ┌─────────────────────────────────┐
   │  ai.saveConversation             │  → Postgres aiConversation row
   │  (now also writes to Mem0 ─────▶│  → Mem0 ingestion (next session sees it)
   │   via fire-and-forget hook)      │
   └─────────────────────────────────┘
```

## Pi-portability seam

When the Raspberry Pi voice daemon ships in Phase 2, only ONE Swift file moves the line: `VoiceToolRegistry.VoiceToolExecutor`. The macOS implementation (`MacVoiceToolExecutor`) calls into `MacAIChatService`. The Pi will provide its own `VoiceToolExecutor` that hits the same tRPC endpoints (`tasks.create`, `tasks.update`, `tasks.delete`) over HTTP.

Everything else is already a thin client over the backend:

- System prompt fetch — `VoiceSystemPromptClient` is plain HTTP
- WS transport — `GeminiLiveProvider` speaks Gemini Live BidiGenerateContent (platform-neutral)
- State machine — concept ports; the Swift code does not
- Audio I/O — AVAudioEngine vs ALSA/PulseAudio (reimplement)
- Trigger — Carbon hotkey vs GPIO button

## Verification

```bash
# 1. Build
xcodegen generate                                                 # apps/macos/
xcodebuild -project apps/macos/TodusMac.xcodeproj \
           -scheme TodusMac -configuration Debug build            # build green

cd apps/server && pnpm exec tsc --noEmit                          # voice files clean (pre-existing noise unrelated)

# 2. Smoke test the new backend route (with a JWT from /api/auth/mobile-token):
curl -H "Authorization: Bearer $TODUS_TOKEN" \
     http://localhost:8787/api/ai/voice/system-prompt | jq .

# 3. Acceptance flows (manual):
#    - Hotkey utility: hold ⌘⇧Space → "what time is it" → Todus answers via get_time
#    - Tool call: hold ⌘⇧Space → "add a task called weblab review for tomorrow" → task appears in Tasks
#    - Memory roundtrip: hold ⌘⇧Space → "remember I'm working on Weblab this quarter" → release → wait → quit/relaunch → hotkey → "what am I working on?" → Todus says Weblab
#    - Permission denied: revoke mic in System Settings → relaunch → hotkey is a safe no-op
#    - Wake fallback: app logs "[Wake] disabled — hotkey only" — hotkey path still works
```

## Files

- Backend: `apps/server/src/routes/ai.ts` (new `/voice/system-prompt` route), `apps/server/src/trpc/routes/ai/conversations.ts` (Mem0 ingest hook)
- macOS Voice services: `apps/macos/TodusMac/Services/Voice/{VoiceSystemPromptClient,VoiceToolRegistry,AudioInputBroker,HotkeyService,WakeWordService,VoiceSessionCoordinator}.swift`
- macOS Voice UI: `apps/macos/TodusMac/Views/Voice/{MacVoiceChatPanel,VoiceStatusWindow}.swift`
- macOS bridge: `apps/macos/TodusMac/Services/AI/MacAIChatService.swift` (`executeVoiceTool`)
- macOS wiring: `apps/macos/TodusMac/App/{MacAppServices,TodusMacApp}.swift`, `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift` (`voiceAssistantSection`)

## Phase 1.5 — wiring Porcupine

1. Add Porcupine SPM in `apps/macos/project.yml` under the `TodusMac` target's packages list.
2. Sign up at https://picovoice.ai/console/ for a free AccessKey (personal use).
3. In `WakeWordService.start()`, replace the stub with a real `Porcupine` recognizer initialized with the built-in `"computer"` keyword.
4. Register the Porcupine consumer with `AudioInputBroker.addConsumer { data in … }` — it converts to the Int16 frame format Porcupine expects (already 16kHz mono).
5. Add a Settings card under "Voice Assistant" to paste the AccessKey into Keychain. The fallback UserDefaults read in `WakeWordService` is dev-only.

After 1.5, the same coordinator handles wake-triggered sessions identically to hotkey-triggered ones — no code change above the trigger layer.

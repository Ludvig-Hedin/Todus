---
id: 0083
title: "Voice Chat Bug Fixes — Double Disconnect, Data Race, Robustness"
status: archived
category: Fixed
release_date: 2026-03-29
source: CHANGELOG.md
---

## [2026-03-29] Voice Chat Bug Fixes — Double Disconnect, Data Race, Robustness

### Summary

Fixed two critical bugs and multiple robustness issues in the Live Voice Chat feature:

**Bug 1 — Double disconnect duplicates chat messages:** Both Close/End Call buttons called `disconnect()` then `dismiss()`, triggering `onDisappear` which called `disconnect()` again. Without an early-return guard, `finalizedTurns` was iterated twice, duplicating all voice messages in chat history. Fix: added `guard connectionState != .disconnected` at top of `disconnect()` and clear `finalizedTurns` after writing.

**Bug 2 — Data race on `isMicMuted`:** The `@MainActor`-isolated `isMicMuted` was read from the audio processing thread in the `installTap` callback and the DispatchSource timer. Fix: added a lock-protected `_micMutedAtomic` Bool that audio threads read, synced from `toggleMute()`.

**Additional fixes:**

- Simplified redundant `connect()` guard that only matched `.failed("")` instead of any `.failed` case
- Provider is now disconnected if audio capture setup fails after a successful connection
- `sendText()` now checks connection state before sending
- Tool call status tracking prevents concurrent tool calls from clobbering each other's UI status
- `sendToolResponse` errors are now logged instead of silently swallowed
- AVAudioConverter input block correctly returns `.noDataNow` after first data supply
- AudioPlayerManager: force-unwrap replaced with guard-let + fatalError; `isPlaying` getter synchronized on audioQueue; playback state resets when scheduled buffers complete naturally
- GeminiLiveProvider: event stream recreated on `connect()` (no longer single-use); URLSession stored and invalidated on disconnect; send functions throw `.notConnected` instead of silent return; receive loop error handler cleans up WebSocket state; `goAway` emits `.disconnected` (no auto-reconnect exists); `sendJSON` throws on nil webSocketTask; setup failure cleans up connection
- Voice tool calls now respect `aiCanWriteTasks` permission (matches text chat path)
- Tool result JSON built with `JSONEncoder` instead of string interpolation (prevents breakage from special characters in task titles)
- Calendar event creation errors propagated instead of silently swallowed
- `shouldSearchWeb()` evaluates time-sensitive keywords before short-command check (so "weather today" triggers search)
- Added `:focus-visible` keyboard focus styles for `.editor-suggestion-item` (WCAG 2.1 AA accessibility)

### Updated Files

- `apps/ios/Todus/Todus/Features/Voice/VoiceChatViewModel.swift` — disconnect guard, clear finalizedTurns, thread-safe mic flag, connect guard simplification, audio capture failure cleanup, sendText connection check, tool call tracking, converter fix
- `apps/ios/Todus/Todus/Services/Voice/AudioPlayerManager.swift` — safe init, synchronized isPlaying, buffer completion tracking
- `apps/ios/Todus/Todus/Services/Voice/GeminiLiveProvider.swift` — reusable event stream, URLSession lifecycle, throw on not-connected, receive loop cleanup, goAway state fix, sendJSON guard
- `apps/ios/Todus/Todus/Services/AI/AIChatService.swift` — aiCanWriteTasks check, encodeToolResult helper, calendar error handling
- `apps/server/src/routes/ai.ts` — shouldSearchWeb ordering fix
- `apps/mail/components/create/prosemirror.css` — focus-visible keyboard accessibility

### Skipped (verified not real bugs)

- VoiceTokenService race condition: class is `@MainActor`, so calls are serialized by the actor executor
- Raw API key in `/ai/voice-token`: Gemini Live requires direct client WebSocket — no way to proxy bidirectionally without a full relay server

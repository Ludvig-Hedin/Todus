---
id: 0070
title: "Live Voice Chat — Gemini Live API Integration"
status: archived
category: Changed
release_date: 2026-03-28
source: CHANGELOG.md
---

## [2026-03-28] Live Voice Chat — Gemini Live API Integration

### Summary

Production-quality bidirectional voice chat with AI assistant using Gemini Live API. Provider-agnostic architecture (protocol abstraction for future OpenAI Realtime support). No API keys in the iOS binary — backend mints short-lived tokens. Full tool call support (create tasks, send emails, create calendar events) during voice sessions.

### Backend (`apps/server/src/routes/ai.ts`)

- Added `POST /ai/voice-token` endpoint: returns `GOOGLE_GENERATIVE_AI_API_KEY` with 5-minute TTL and model name, gated by Bearer auth

### iOS — New Files

- `Services/Voice/VoiceProvider.swift` — Protocol + enums (`VoiceConnectionState`, `TranscriptRole`, `VoiceSessionEvent`) + `VoiceSessionConfig` struct
- `Services/Voice/GeminiLiveProvider.swift` — WebSocket implementation using native `URLSessionWebSocketTask`, handles Gemini Live bidirectional protocol
- `Services/Voice/VoiceTokenService.swift` — Fetches and caches tokens from backend
- `Services/Voice/AudioPlayerManager.swift` — Plays PCM16 24kHz audio chunks via `AVAudioEngine` + `AVAudioPlayerNode`
- `Features/Voice/VoiceChatViewModel.swift` — @Observable ViewModel: manages provider, audio capture (PCM16 16kHz), transcript state, tool call routing
- `Features/Voice/VoiceChatModalView.swift` — Full-screen modal: transcript area, animated listening/speaking indicator, mic mute/end call controls

### iOS — Modified Files

- `AIChatService.swift` — Added `appendVoiceExchange()`, `buildSystemPromptForVoice()`, `processVoiceToolCall()`, `voiceToolDeclarations()`
- `AIChatMessage.swift` — Added `MessageSource` enum (.text/.voice) with `source` property
- `AIChatView.swift` — Added waveform button (AI gradient) in both expanded/compact chat input modes + `.fullScreenCover` for voice modal
- `AppServices.swift` — Added `VoiceTokenService` registration

### Architecture Notes

- Voice transcripts stay local in the modal; only finalized exchanges are written to main chat history on disconnect
- Tool calls route through existing `AIChatService` pipeline
- Audio: capture PCM16 @ 16kHz via AVAudioEngine → 100ms chunks → WebSocket; playback PCM16 @ 24kHz

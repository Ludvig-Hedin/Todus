---
id: 0222
title: "DONE Voice assistant parity (iOS) — Services/Voice/VoiceSessionCoordinator.swift (391L state machine"
status: done
tags: [task-md, sprint]
files: [Services/Voice/VoiceSessionCoordinator.swift, VoiceSystemPromptClient.swift, VoiceToolRegistry.swift, VoiceAudioCapture.swift, VoiceIntent.swift, Features/Settings/VoiceAssistantSettingsView.swift]
created: 2026-05-17
source: TASK.md
---

> Source context: TASK.md → Current iOS Parity + Hardening Sprint (2026-05-17)

- `DONE` **Voice assistant parity (iOS)** — `Services/Voice/VoiceSessionCoordinator.swift` (391L state machine: idle/connecting/listening/speaking/toolRunning/error), `VoiceSystemPromptClient.swift` (60s cache + offline fallback), `VoiceToolRegistry.swift` (Gemini function declarations + `VoiceToolExecutor` protocol + iOS adapter calling `AIChatService.processVoiceToolCall`), `VoiceAudioCapture.swift` (AVAudioEngine 16kHz PCM16 capture split out for line-cap), `VoiceIntent.swift` (`StartVoiceAssistantIntent` AppIntent with `openAppWhenRun = true` + `TodusVoiceAppShortcuts` provider), `Features/Settings/VoiceAssistantSettingsView.swift`. Wired into `AppServices` + `TodosApp` (`.task` subscribes to `.todusStartVoiceSession` notification). Settings entry added under AI Assistant section.

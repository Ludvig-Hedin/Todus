---
id: 0173
title: "Fix — iOS/macOS transcribe freeze, AI chat input layout redesign"
status: archived
category: Fixed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] Fix — iOS/macOS transcribe freeze, AI chat input layout redesign

- **Transcribe freeze fix (iOS + macOS):** Moved ALL heavy audio operations (AVAudioSession.setActive, AVAudioEngine.inputNode, engine.prepare(), engine.start()) off the main thread using `@unchecked Sendable` holder classes + `Task.detached`. Previously only `setActive` was off-main; `inputNode` access and `engine.start()` still blocked for several seconds during hardware init.
- Three separate implementations fixed: `ChatVoiceInputButton.VoiceRecorder` (AIChatView.swift), `VoiceController` via new `AudioEngineHolder` (VoiceInputButton.swift), `MacVoiceController` via new `MacAudioEngineHolder` (MacAssistantPanel.swift).
- Redesigned AI chat input to two-row layout: full-width text field on top, button row below. Fixes text being pushed right and not full-width.
- Fixed 9+ second input freeze caused by GeometryReader layout cycle in the old single-row HStack.
- Full-screen expand button only shown when text reaches max height (≥118pt), with consistent 30×30 sizing.
- Fixed multiline input sliding below keyboard in empty state: moved `inputSection` into `.safeAreaInset(edge: .bottom)` — same pattern as `conversationView` — so the input bottom is always pinned just above the keyboard regardless of how many lines are typed.

**Files:** `apps/ios/Todus/Todus/Features/Voice/VoiceInputButton.swift`, `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`, `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift`

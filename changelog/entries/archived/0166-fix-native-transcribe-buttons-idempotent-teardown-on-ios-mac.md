---
id: 0166
title: "Fix — Native transcribe buttons: idempotent teardown on iOS + macOS"
status: archived
category: Fixed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] Fix — Native transcribe buttons: idempotent teardown on iOS + macOS

- **iOS (`VoiceInputButton.swift`, `AIChatView.swift`):** Made speech-recorder teardown idempotent so repeated stop/final/error callbacks can no longer double-remove audio taps or double-deliver transcripts. Added tap-tracking, guarded re-entry, and safer finalization for both the shared voice button and the AI chat transcribe button.
- **macOS (`MacAssistantPanel.swift`):** Applied the same stop/finalization hardening to the macOS speech input controller so the assistant transcribe button no longer races engine shutdown against recognizer callbacks.
- This specifically targets the freeze/close-on-press behavior reported around the transcribe button by preventing invalid audio-engine lifecycle transitions while the Speech framework is still unwinding.

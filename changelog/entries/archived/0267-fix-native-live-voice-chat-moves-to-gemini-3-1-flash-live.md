---
id: 0267
title: "Fix — native live voice chat moves to Gemini 3.1 Flash Live"
status: archived
category: Fixed
release_date: 2026-04-26
source: CHANGELOG.md
---

## [2026-04-26] Fix — native live voice chat moves to Gemini 3.1 Flash Live

- [Fix] **iOS + macOS live voice chat now use Google’s current Live API model.** The shared native voice-session defaults no longer point at deprecated `models/gemini-2.0-flash-live-001`; both apps now open sessions with `gemini-3.1-flash-live-preview`, matching Google’s current Live model docs and avoiding the rejected `bidiGenerateContent` setup seen in production.
- [Fix] **Live-session text updates now use realtime input.** Mid-call text is now sent as `realtimeInput.text` instead of `clientContent`, aligning the native providers with the current Gemini Live API contract for in-session text.
- [User-facing] **Voice UI now names the active model.** The iOS and macOS live-voice headers show `Gemini 3.1 flash live` so the surfaced model name matches the runtime model actually used for voice sessions.
- [Verification] **iOS native build passed.** `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -configuration Debug -destination 'generic/platform=iOS' build` succeeded after the patch. The macOS target remains blocked by a pre-existing unrelated compile error in `apps/macos/TodusMac/App/TodusMacApp.swift` (`FolderItemRecord` not found), so full macOS build verification could not complete from this branch state.
- [Files] `apps/ios/Todus/Todus/Services/Voice/VoiceProvider.swift`, `apps/ios/Todus/Todus/Services/Voice/GeminiLiveProvider.swift`, `apps/ios/Todus/Todus/Features/Voice/VoiceChatModalView.swift`, `apps/macos/TodusMac/Services/Voice/VoiceProvider.swift`, `apps/macos/TodusMac/Services/Voice/GeminiLiveProvider.swift`, `apps/macos/TodusMac/Views/Voice/MacVoiceChatPanel.swift`, `CHANGELOG.md`, `TASK.md`

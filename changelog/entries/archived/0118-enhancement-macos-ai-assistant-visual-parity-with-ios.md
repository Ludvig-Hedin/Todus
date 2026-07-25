---
id: 0118
title: "Enhancement — macOS AI Assistant visual parity with iOS"
status: archived
category: Changed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Enhancement — macOS AI Assistant visual parity with iOS

Second pass to match the iOS AIChatView pixel-for-pixel. Key additions:

- **Page context chip**: Blue pill (e.g. "🏠 Home ×") showing current view, removable by user
- **Context-aware suggestions**: Suggestion pools change per active page (Home/Tasks/Email/Calendar) matching iOS
- **Show more / Show less**: Expandable suggestions with shuffle-on-refresh, matching iOS behavior
- **Prompt library**: Popover with 12 categorized prompt templates (Writing, Planning, Email, etc.)
- **Voice input (mic)**: Full speech-to-text via macOS Speech framework + AVAudioEngine, matching iOS VoiceInputButton
- **Attachment button (+)**: File picker for attaching documents, with removable pill previews
- **Thumbs up/down feedback**: Added to action row matching iOS
- **Animated sparkle icon**: Rotating gradient sparkles icon matching iOS AnimatedSparkleIcon
- **Reasoning box**: Collapsible thinking box with auto-expand/collapse matching iOS ReasoningBox
- **Darker background**: Panel background now matches iOS dark theme
- **Rounded input box**: Input section wrapped in rounded surface card matching iOS chatInputBox design
- **Draft persistence**: Input text saved/restored via UserDefaults
- **Rename conversation**: Alert dialog for renaming chat title
- **Microphone permissions**: Added NSMicrophoneUsageDescription + NSSpeechRecognitionUsageDescription to Info.plist
- **Wider panel**: Floating 400×560 (was 380×520), side pane 380 (was 360) for more breathing room

**Files changed:**

- `MacAssistantPanel.swift` — Complete rewrite with ~900 lines of iOS-parity UI
- `MacRootView.swift` — Passes `selection` to panel for page context chip
- `Info.plist` — Added microphone and speech recognition usage descriptions

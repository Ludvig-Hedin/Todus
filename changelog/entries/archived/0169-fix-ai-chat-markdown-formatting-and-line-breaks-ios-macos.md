---
id: 0169
title: "Fix — AI chat markdown formatting and line breaks (iOS + macOS)"
status: archived
category: Fixed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] Fix — AI chat markdown formatting and line breaks (iOS + macOS)

- **Instant markdown rendering (iOS + macOS):** AI responses now render headings (`#`), bullets (`-`), bold, and code blocks _during streaming_ instead of showing raw markdown characters. Removed the two-phase `showFullMarkdown` toggle — `fullMarkdownText` (`.full` AttributedString syntax) is used from the first token. Typewriter animation is preserved; the blinking cursor overlay continues during streaming.
- **macOS multiline input:** Replaced SwiftUI `TextField` + `onSubmit` with a custom `NSViewRepresentable` (`MacChatTextInput`) wrapping `NSTextView`. Return now inserts a line break; **Cmd+Return** sends the message. The send button tooltip updated to `⌘↵`.
- **User bubble line breaks (iOS + macOS):** Added `.fixedSize(horizontal: false, vertical: true)` to `Text(message.content)` in user bubbles to guarantee vertical expansion for multi-line messages.
- Added `MacBlinkingCursor` component on macOS to show a blinking cursor during AI streaming.

**Files:** `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`, `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift`

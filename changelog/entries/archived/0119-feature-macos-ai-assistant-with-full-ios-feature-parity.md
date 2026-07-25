---
id: 0119
title: "Feature — macOS AI Assistant with full iOS feature parity"
status: archived
category: Added
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Feature — macOS AI Assistant with full iOS feature parity

Complete rewrite of the macOS AI assistant to achieve 100% feature parity with the iOS app. Replaced the placeholder `.sheet()` modal with an inline chat panel supporting two display modes.

### Display Modes

- **Floating mode**: draggable overlay window (380×520) anchored bottom-right, stays open while navigating
- **Side pane mode**: docked 360px panel on the right edge, integrated into the main layout
- Toggle between modes via header button; ⌘L toggles open/close; FAB hides when panel is open

### Streaming & Tool Calls (iOS parity)

- Full SSE streaming with 40ms token batching for smooth typewriter animation
- Tool call processing: `create_task`, `update_task`, `delete_task`, `create_calendar_event`, `send_email`
- Task CRUD mutations applied directly to SwiftData via ModelContext
- Calendar events created via CalendarService actor
- Email sending via EmailService

### Web Search & Reasoning

- `search_status` SSE events show animated search indicator with rotating status text
- `sources` SSE events rendered as clickable source chips (opens URL in browser)
- `reasoning` / `reasoning_done` events displayed in collapsible disclosure group

### Conversation History

- Full conversation persistence to UserDefaults (50-conversation cap)
- History popover for browsing and resuming past conversations
- New conversation button, auto-save on panel hide

### UI Polish

- Inline-only markdown during streaming for performance, full CommonMark after streaming ends
- Action row per message: retry (removes dependent turns) + copy with checkmark feedback
- Model picker (gpt-4.1, o4-mini, gpt-4.1-mini) in header
- Mutation chips with color-coded action badges (green=create, blue=update, red=delete)
- Suggestion chips for empty state quick prompts

**Files created:**

- `apps/macos/TodusMac/Services/AI/MacAIChatService.swift` — full AI chat service with SSE, tool calls, history, retry
- `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift` — polished chat panel with dual display modes

**Files changed:**

- `apps/macos/TodusMac/App/MacAppServices.swift` — added `aiChatService` with calendarService dependency
- `apps/macos/TodusMac/App/MacRootView.swift` — replaced `.sheet()` with inline floating/sidepane panel
- `apps/macos/TodusMac.xcodeproj/project.pbxproj` — registered new files and groups

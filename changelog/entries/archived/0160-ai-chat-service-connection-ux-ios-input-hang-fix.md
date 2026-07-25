---
id: 0160
title: "AI Chat — Service Connection UX + iOS Input Hang Fix"
status: archived
category: Fixed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] AI Chat — Service Connection UX + iOS Input Hang Fix

### iOS (`apps/ios/Todus`)

- **Fix: Input-tap hang** — Capped `mentionOptions` thread iteration at 50 entries before dictionary grouping, preventing O(n) main-thread freeze when tapping the AI chat input field.
- **Service connection messaging** — Updated system prompt: AI now says "Calendar/Email is not connected" instead of "access disabled by user". AI is told to direct users to connect in settings.
- **Suggestion filtering** — Calendar tab returns no suggestions (shows connect CTA instead) when EventKit permission is not granted. Email tab does the same when inbox is not loaded.
- **Connect CTA in messages** — `MessageBubble` detects when a service is mentioned in an AI response while that service is disconnected, and shows a compact "Connect Calendar / Email" pill button inline.
- **Connect CTA in empty state** — When the active tab's suggestion pool is empty, a `connectServicesPrompt` shows compact capsule buttons to request calendar access or navigate to email.

### macOS (`apps/macos/TodusMac`)

- **Service connection messaging** — Same system prompt update as iOS. AI says "not connected" for calendar/email when not available.
- **Suggestion filtering** — Calendar and email sections return empty pools when respective services aren't connected; connect prompt shown instead.
- **Connect CTA in messages** — `MacMessageBubble` shows connect banner when AI mentions a disconnected service.

### Web (`apps/mail`)

- **Markdown rendering** — Fixed `markdownStyles` to give headings visual hierarchy (bold/semibold weight), proper paragraph/list sizing, `outside` list-item positioning, styled code blocks, and blockquote styling. Added `normalizeMarkdown()` to convert single `\n` to `\n\n` so CommonMark sees paragraph breaks.
- **Suggestion filtering** — `ExampleQueries` hides all email suggestions when no email connection exists and shows a "Connect Email Account" link instead.
- **Connect CTA in messages** — Inline `<a>` to `/settings/connections` shown below assistant messages that mention "email", "inbox", or "not connected" when no email account is linked.
- **Chat entitlement gating** — `isChatEnabled` now blocks chat until billing has finished loading and the feature is confirmed enabled, so users do not get access before entitlement is known.

### Files changed

- `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`
- `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`
- `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift`
- `apps/macos/TodusMac/Services/AI/MacAIChatService.swift`
- `apps/mail/components/create/ai-chat.tsx`

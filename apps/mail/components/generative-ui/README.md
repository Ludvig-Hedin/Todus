# Generative UI — Chat Card Rendering System

Renders rich, interactive cards (email, task, calendar, etc.) inline within AI chat messages. Uses [json-render](https://json-render.dev/) on web and a custom SwiftUI renderer on iOS, both consuming the same JSON spec format.

## Architecture

```
AI (backend) ──generates──> JSON UI Spec ──consumed by──> React Renderer (web)
                                                      └──> SwiftUI Renderer (iOS)
```

The AI embeds specs as ` ```ui-spec ` code blocks in chat messages. Both platforms parse and render them inline.

## Spec Format

```json
{
  "root": "stack-1",
  "elements": {
    "stack-1": {
      "type": "Stack",
      "props": { "direction": "vertical", "gap": "sm" },
      "children": ["email-1"]
    },
    "email-1": {
      "type": "EmailCard",
      "props": {
        "threadId": "abc123",
        "sender": "Jane Smith",
        "senderEmail": "jane@example.com",
        "subject": "Q1 Report",
        "snippet": "Please review...",
        "receivedAt": "2026-03-27T10:30:00Z",
        "isUnread": true,
        "labels": [{ "name": "to respond", "color": null }]
      }
    }
  }
}
```

## Available Card Types

| Type | Props | Use Case |
|------|-------|----------|
| `EmailCard` | threadId, sender, senderEmail, subject, snippet, receivedAt, isUnread, labels | Email thread preview |
| `TaskCard` | taskId, title, description, status, priority, dueDate, folderName, emailThreadId | Task/to-do item |
| `CalendarEventCard` | eventId, title, start, end, location, isAllDay, attendees | Calendar event |
| `NoteCard` | noteId, content, color, isPinned, threadId | Thread note |
| `DraftCard` | draftId, to, subject, snippet, updatedAt | Email draft |
| `LabelCard` | labelId, name, color, count | Email label |
| `ContactCard` | name, email, avatarUrl | Contact/sender |
| `SearchResultCard` | query, resultCount, summary | Search summary header |

## Layout Components

| Type | Props | Has Children |
|------|-------|-------------|
| `Stack` | direction, gap, align | Yes |
| `Card` | title, description, padding | Yes |
| `Text` | content, variant | No |
| `Button` | label, action, actionParams, variant | No |
| `Badge` | label, variant | No |
| `Divider` | (none) | No |

## Adding a New Card Type

1. **Catalog** (`catalog.ts`): Add component with zod props schema
2. **React** (`components/<Name>.tsx`): Implement the React component
3. **Registry** (`registry.tsx`): Register the component implementation
4. **iOS** (`GenerativeUI/CardViews.swift`): Add SwiftUI view
5. **iOS Models** (`GenerativeUI/ChatUISpec.swift`): Add props struct
6. **iOS Renderer** (`GenerativeUI/ChatUISpecView.swift`): Add case to switch
7. **Backend** (`generative-ui-contract.ts`): Add to component docs and prompt

## File Locations

### Web (React)
- `apps/mail/components/generative-ui/catalog.ts` — Catalog definition (zod schemas)
- `apps/mail/components/generative-ui/registry.tsx` — Component registry
- `apps/mail/components/generative-ui/ChatSpecRenderer.tsx` — Top-level renderer
- `apps/mail/components/generative-ui/components/` — Individual card components

### iOS (SwiftUI)
- `apps/ios/Todus/.../AI/GenerativeUI/ChatUISpec.swift` — Models + parser
- `apps/ios/Todus/.../AI/GenerativeUI/ChatUISpecView.swift` — Renderer + layout views
- `apps/ios/Todus/.../AI/GenerativeUI/CardViews.swift` — Domain card views

### Backend
- `apps/server/src/lib/generative-ui-contract.ts` — Schema + system prompt fragment
- `apps/server/src/lib/prompts.ts` — Injected into AI system prompt

## Actions

Cards can trigger actions when tapped:

| Action | Params | Behavior |
|--------|--------|----------|
| `navigate_thread` | `{ threadId }` | Open email thread |
| `navigate_task` | `{ taskId }` | Open task detail |
| `navigate_event` | `{ eventId }` | Open calendar event |
| `archive_email` | `{ threadIds }` | Archive threads |
| `mark_read` | `{ threadIds }` | Mark as read |
| `mark_unread` | `{ threadIds }` | Mark as unread |
| `complete_task` | `{ taskId }` | Mark task done |
| `delete_task` | `{ taskId }` | Delete task |

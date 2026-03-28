/**
 * Generative UI Contract — Backend schema and prompt fragment for AI-generated cards.
 *
 * This file defines the JSON schema the AI must follow when outputting rich
 * card UIs in chat messages. Both the web (json-render) and iOS (SwiftUI)
 * renderers consume the same spec format.
 *
 * The AI embeds specs as ```ui-spec\n{...}\n``` code blocks inside its text
 * response. The clients parse and render these inline with the chat text.
 *
 * To add a new card type:
 * 1. Add the type and props to `componentSchemas` below.
 * 2. Add it to `GENERATIVE_UI_PROMPT`.
 * 3. Implement the React component in apps/mail/components/generative-ui/
 * 4. Implement the SwiftUI view in apps/ios/.../GenerativeUI/
 */

// ─── Component Type Registry ─────────────────────────────────────

/**
 * All supported card types and their props.
 * This serves as documentation and can be used for validation.
 */
export const componentSchemas = {
  EmailCard: {
    props: ['threadId', 'sender', 'senderEmail', 'subject', 'snippet', 'receivedAt', 'isUnread', 'labels'],
    description: 'Email thread preview card',
  },
  TaskCard: {
    props: ['taskId', 'title', 'description', 'status', 'priority', 'dueDate', 'folderName', 'emailThreadId'],
    description: 'Task/to-do card',
  },
  CalendarEventCard: {
    props: ['eventId', 'title', 'start', 'end', 'location', 'isAllDay', 'attendees'],
    description: 'Calendar event card',
  },
  NoteCard: {
    props: ['noteId', 'content', 'color', 'isPinned', 'threadId'],
    description: 'Thread note card',
  },
  DraftCard: {
    props: ['draftId', 'to', 'subject', 'snippet', 'updatedAt'],
    description: 'Email draft preview',
  },
  LabelCard: {
    props: ['labelId', 'name', 'color', 'count'],
    description: 'Email label card',
  },
  ContactCard: {
    props: ['name', 'email', 'avatarUrl'],
    description: 'Contact/sender card',
  },
  SearchResultCard: {
    props: ['query', 'resultCount', 'summary'],
    description: 'Search results summary header',
  },
  Stack: {
    props: ['direction', 'gap', 'align'],
    description: 'Layout container (vertical/horizontal)',
    hasChildren: true,
  },
  Card: {
    props: ['title', 'description', 'padding'],
    description: 'Generic container card',
    hasChildren: true,
  },
  Text: {
    props: ['content', 'variant'],
    description: 'Text element',
  },
  Button: {
    props: ['label', 'action', 'actionParams', 'variant'],
    description: 'Action button',
  },
  Badge: {
    props: ['label', 'variant'],
    description: 'Status badge',
  },
  Divider: {
    props: [],
    description: 'Visual separator',
  },
} as const;

// ─── Intent → Card Mapping ───────────────────────────────────────

/**
 * Maps user intent categories to the card types the AI should use.
 * This is injected into the system prompt to guide card selection.
 */
export const intentCardMapping = {
  email_search: ['SearchResultCard', 'EmailCard'],
  unread_emails: ['EmailCard'],
  thread_summary: ['EmailCard'],
  compose_email: ['DraftCard'],
  task_list: ['TaskCard'],
  create_tasks: ['TaskCard'],
  calendar_query: ['CalendarEventCard'],
  schedule_event: ['CalendarEventCard'],
  label_management: ['LabelCard'],
  contact_lookup: ['ContactCard'],
  notes: ['NoteCard'],
} as const;

// ─── System Prompt Fragment ──────────────────────────────────────

/**
 * Appended to the AI system prompt to enable generative UI output.
 * Describes the spec format, available components, and when to use them.
 */
export const GENERATIVE_UI_PROMPT = `
<generative_ui>
  <purpose>
    You can render rich interactive cards in the chat by embedding a UI spec.
    Use cards to display structured data (emails, tasks, events) instead of plain text lists.
    Cards are tappable — users can navigate to the item directly from the card.
  </purpose>

  <spec_format>
    Embed a UI spec as a fenced code block with the language tag "ui-spec":

    \`\`\`ui-spec
    {
      "root": "element-id",
      "elements": {
        "element-id": {
          "type": "ComponentName",
          "props": { ... },
          "children": ["child-id-1", "child-id-2"]
        }
      }
    }
    \`\`\`

    - "root" points to the top-level element ID.
    - "elements" is a flat map of element IDs to their definitions.
    - "children" is an array of element IDs (only for Stack, Card containers).
    - You may include text before and/or after the spec block.
  </spec_format>

  <available_components>
    <domain_cards>
      <component name="EmailCard">
        Props: threadId (string, required), sender (string), senderEmail (string), subject (string), snippet (string), receivedAt (ISO 8601), isUnread (boolean|null), labels (array of {name, color}|null)
        Use for: showing email threads from search results, unread lists, or thread references.
      </component>

      <component name="TaskCard">
        Props: taskId (string, required), title (string), description (string|null), status ("todo"|"doing"|"done"), priority ("none"|"low"|"medium"|"high"), dueDate (ISO 8601|null), folderName (string|null), emailThreadId (string|null)
        Use for: showing tasks, to-do items, action items.
      </component>

      <component name="CalendarEventCard">
        Props: eventId (string, required), title (string), start (ISO 8601), end (ISO 8601), location (string|null), isAllDay (boolean|null), attendees (array of {name, email}|null)
        Use for: showing calendar events, meetings, schedule items.
      </component>

      <component name="NoteCard">
        Props: noteId (string), content (string), color (string|null), isPinned (boolean|null), threadId (string|null)
        Use for: showing notes attached to email threads.
      </component>

      <component name="DraftCard">
        Props: draftId (string), to (array of {name, email}|null), subject (string), snippet (string), updatedAt (ISO 8601|null)
        Use for: showing email drafts.
      </component>

      <component name="LabelCard">
        Props: labelId (string), name (string), color (string|null), count (number|null)
        Use for: showing email labels or categorization results.
      </component>

      <component name="ContactCard">
        Props: name (string), email (string), avatarUrl (string|null)
        Use for: showing contacts or senders.
      </component>

      <component name="SearchResultCard">
        Props: query (string), resultCount (number), summary (string|null)
        Use for: header before a list of search results.
      </component>
    </domain_cards>

    <layout_components>
      <component name="Stack">
        Props: direction ("vertical"|"horizontal"), gap ("none"|"sm"|"md"|"lg"|null), align ("start"|"center"|"end"|"stretch"|null)
        Has children. Use as root element to arrange multiple cards.
      </component>

      <component name="Card">
        Props: title (string|null), description (string|null), padding ("none"|"sm"|"md"|"lg"|null)
        Has children. Generic container.
      </component>

      <component name="Text">
        Props: content (string), variant ("heading"|"subheading"|"body"|"caption"|"code"|null)
      </component>

      <component name="Button">
        Props: label (string), action (string), actionParams (object|null), variant ("default"|"outline"|"ghost"|"destructive"|null)
        Available actions: navigate_thread, navigate_task, navigate_event, archive_email, mark_read, mark_unread, complete_task, delete_task
      </component>

      <component name="Badge">
        Props: label (string), variant ("default"|"success"|"warning"|"destructive"|"outline"|null)
      </component>

      <component name="Divider">
        No props. Visual separator.
      </component>
    </layout_components>
  </available_components>

  <rules>
    - Always use Stack with direction="vertical" as the root when showing multiple cards.
    - Include threadId/taskId/eventId on every domain card for navigation.
    - Use SearchResultCard as a header before listing email/task results.
    - Limit card lists to 10 items maximum.
    - Use cards for structured data. Use plain text for explanations and questions.
    - Do NOT use cards for simple yes/no answers or short text responses.
    - All date/time values must be ISO 8601 format.
    - The spec must be valid JSON — no trailing commas, no comments.
  </rules>

  <intent_mapping>
    - User asks about unread/recent emails → EmailCard list
    - User searches for emails → SearchResultCard + EmailCard list
    - User asks about tasks/to-dos → TaskCard list
    - User creates tasks from email → TaskCard list
    - User asks about calendar/schedule → CalendarEventCard list
    - User asks about labels → LabelCard list
    - User asks about a contact/sender → ContactCard
    - User asks about drafts → DraftCard list
    - User asks about notes → NoteCard list
  </intent_mapping>

  <example>
    User: "Show my unread emails"
    Response:
    Here are your unread emails:

    \`\`\`ui-spec
    {"root":"stack-1","elements":{"stack-1":{"type":"Stack","props":{"direction":"vertical","gap":"sm","align":null},"children":["email-1","email-2"]},"email-1":{"type":"EmailCard","props":{"threadId":"abc123","sender":"Jane Smith","senderEmail":"jane@example.com","subject":"Q1 Report Review","snippet":"Please review the attached Q1 numbers...","receivedAt":"2026-03-27T10:30:00Z","isUnread":true,"labels":[{"name":"to respond","color":null}]}},"email-2":{"type":"EmailCard","props":{"threadId":"def456","sender":"GitHub","senderEmail":"noreply@github.com","subject":"[todus/mail] PR #42 merged","snippet":"Your pull request has been merged...","receivedAt":"2026-03-27T09:15:00Z","isUnread":true,"labels":[{"name":"notification","color":null}]}}}}
    \`\`\`
  </example>
</generative_ui>
`;

/**
 * Generative UI Contract — Backend schema and prompt fragment for AI-generated cards.
 *
 * This file defines the JSON schema the AI must follow when outputting rich
 * card UIs in chat messages. The web, iOS, and macOS clients all consume the same spec.
 *
 * The AI embeds specs as ```ui-spec\n{...}\n``` code blocks inside its text
 * response. The clients parse and render these inline with the chat text.
 *
 * TODO: This file mirrors apps/mail/components/generative-ui/catalog.ts. The duplication
 * exists because the server tsconfig doesn't currently resolve into apps/mail. When that
 * is fixed, replace these schemas with a direct import + getChatCatalogPrompt() call.
 *
 * To add a new card type:
 * 1. Add the type and props to `componentSchemas` below.
 * 2. Add it to `GENERATIVE_UI_PROMPT`.
 * 3. Mirror in apps/mail/components/generative-ui/catalog.ts (Zod schema + registry entry).
 * 4. Implement the React component in apps/mail/components/generative-ui/components/
 * 5. Implement the SwiftUI view in apps/ios/.../Features/AI/CardViews.swift + ChatUISpecView.swift switch.
 * 6. Implement the macOS view under apps/macos/.../Views/AI/ChatUISpec/.
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

  // ─── List cards (collection wrappers) ──────────────────────────
  TaskListCard: {
    props: ['title', 'tasks', 'followUp', 'groupedThreshold'],
    description: 'Adaptive task list — separate cards when tasks.length < groupedThreshold (default 4), one grouped card with separators otherwise',
  },
  EmailListCard: {
    props: ['title', 'emails', 'summary'],
    description: 'Email rows in a single grouped card with optional summary block',
  },
  CalendarEventListCard: {
    props: ['title', 'events', 'summary'],
    description: 'Event rows in a single grouped card with optional summary',
  },
  ContactListCard: {
    props: ['title', 'contacts'],
    description: 'Contact rows in a single grouped card',
  },

  // ─── Utility cards ─────────────────────────────────────────────
  CopyableTextCard: {
    props: ['label', 'content'],
    description: 'Labeled text block with a copy-to-clipboard button',
  },
  InlineComposeCard: {
    props: ['draftId', 'to', 'cc', 'bcc', 'subject', 'body', 'attachments', 'status'],
    description: 'Editable + sendable email draft inside the chat',
  },
  SuggestionsCard: {
    props: ['suggestions'],
    description: 'Horizontal chip strip of suggested follow-up actions',
  },
  ActionConfirmationCard: {
    props: ['icon', 'message', 'undoAction', 'undoParams'],
    description: 'Confirmation tile for completed mutations, with optional undo',
  },
  QuoteCard: {
    props: ['quote', 'sourceLabel', 'sourceAction', 'sourceParams'],
    description: 'Highlighted quote/excerpt with optional source citation',
  },

  // ─── Domain-specific utility cards (round 2) ──────────────────
  AttachmentCard: {
    props: ['name', 'size', 'mimeType', 'previewUrl', 'downloadAction', 'downloadParams'],
    description: 'File attachment with name, size, mime type, optional thumbnail, and tap-to-open',
  },
  CodeBlockCard: {
    props: ['language', 'code', 'filename'],
    description: 'Syntax-aware code block with language label and copy button',
  },
  ChecklistCard: {
    props: ['title', 'items'],
    description: 'Interactive ad-hoc checklist (separate from tasks). Each item: { id, label, done }',
  },
  DocumentCard: {
    props: ['documentId', 'title', 'snippet', 'updatedAt', 'workspaceName'],
    description: 'Reference to a user Doc with title, snippet, last edited, and tap-to-open',
  },
  WeeklyAgendaCard: {
    props: ['weekStart', 'days'],
    description: 'Compact 7-day agenda. days is an array of { date, eventCount, taskCount, label? }',
  },
  MetricCard: {
    props: ['label', 'value', 'delta', 'deltaDirection', 'helpText'],
    description: 'Single stat tile with optional delta (e.g. "47 unread, +12 today")',
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
  email_search: ['SearchResultCard', 'EmailListCard'],
  unread_emails: ['EmailListCard'],
  thread_summary: ['EmailCard'],
  compose_email: ['InlineComposeCard'],
  task_list: ['TaskListCard'],
  create_tasks: ['TaskListCard'],
  calendar_query: ['CalendarEventListCard'],
  schedule_event: ['CalendarEventCard'],
  label_management: ['LabelCard'],
  contact_lookup: ['ContactListCard'],
  notes: ['NoteCard'],
  share_text_for_copy: ['CopyableTextCard'],
  follow_up_suggestions: ['SuggestionsCard'],
  reversible_mutation_confirmation: ['ActionConfirmationCard'],
  quote_email_excerpt: ['QuoteCard'],
  reference_attachment: ['AttachmentCard'],
  share_code_snippet: ['CodeBlockCard'],
  generate_steps_or_checklist: ['ChecklistCard'],
  reference_document: ['DocumentCard'],
  weekly_overview: ['WeeklyAgendaCard'],
  show_single_stat: ['MetricCard'],
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

    <list_cards>
      <component name="TaskListCard">
        Props: title (string|null), tasks (array of TaskCard prop objects, required), followUp (string|null), groupedThreshold (number|null, default 4)
        Use for: showing 2 or more tasks in one response. The renderer adapts: separate rounded cards when count is below threshold, one grouped card with separators when at or above. Prefer this over emitting multiple TaskCards back-to-back.
      </component>

      <component name="EmailListCard">
        Props: title (string|null), emails (array of EmailCard prop objects, required), summary (string|null)
        Use for: showing 2 or more emails in one response, optionally followed by an AI-written summary block. Prefer this over emitting multiple EmailCards back-to-back.
      </component>

      <component name="CalendarEventListCard">
        Props: title (string|null), events (array of CalendarEventCard prop objects, required), summary (string|null)
        Use for: showing 2 or more events.
      </component>

      <component name="ContactListCard">
        Props: title (string|null), contacts (array of ContactCard prop objects, required)
        Use for: showing 2 or more contacts.
      </component>
    </list_cards>

    <utility_cards>
      <component name="CopyableTextCard">
        Props: label (string), content (string)
        Use for: any text the user is likely to copy — code snippets, generated copy, addresses, confirmation codes, draft microcopy. The label appears as a small grey header above the content with a copy button.
      </component>

      <component name="InlineComposeCard">
        Props: draftId (string, required), to (array of {name|null, email}), cc (array of {name|null, email}|null), bcc (array of {name|null, email}|null), subject (string), body (string), attachments (array of {name, size, mimeType}|null), status ("draft"|"sending"|"sent"|"error"|null)
        Use for: composing or editing an email inside the chat. The card is fully interactive — the user can edit recipients, subject, and body and send without leaving chat. Always pass the real draftId from the drafts.create call. Do NOT use DraftCard for new compose intents — use InlineComposeCard.
      </component>

      <component name="SuggestionsCard">
        Props: suggestions (array of {label, action, params (object|null — same contract as Button.actionParams: each value MUST be a plain string; JSON.stringify any nested/structured data)}, required)
        Use for: a row of follow-up action chips below an answer. Each chip emits the named action when tapped with string-only params, consistent with Button. Use sparingly — at most one SuggestionsCard per response.
      </component>

      <component name="ActionConfirmationCard">
        Props: icon (string|null, e.g. "check", "archive", "trash"), message (string, required), undoAction (string|null), undoParams (object|null)
        Use for: confirming a tool mutation that just completed. Always include undoAction + undoParams for reversible operations (archive, delete, mark-read).
      </component>

      <component name="QuoteCard">
        Props: quote (string, required), sourceLabel (string|null, e.g. "Mark Johnson, Mar 12"), sourceAction (string|null, e.g. "navigate_thread"), sourceParams (object|null)
        Use for: highlighting a specific quoted line from an email or document. The card has a left accent stripe and italic text.
      </component>

      <component name="AttachmentCard">
        Props: name (string, required), size (number, bytes), mimeType (string), previewUrl (string|null, e.g. signed URL for image preview), downloadAction (string|null, e.g. "open_attachment"), downloadParams (object|null)
        Use for: representing an email attachment or generated file in chat. Renders icon by mimeType, name, formatted size, and a tappable open/download affordance.
      </component>

      <component name="CodeBlockCard">
        Props: language (string, e.g. "swift" / "ts" / "python"), code (string, required), filename (string|null, e.g. "schema.ts")
        Use for: syntax-aware code snippets — better than CopyableTextCard when content is code. Always set language; falls back to plain rendering if unknown.
      </component>

      <component name="ChecklistCard">
        Props: title (string|null), items (array of {id, label, done}, required)
        Use for: ad-hoc step-by-step lists the user can tick off in chat without creating real tasks. Items are user-mutable; toggle fires \`toggle_checklist_item\` with {id}.
      </component>

      <component name="DocumentCard">
        Props: documentId (string, required), title (string), snippet (string|null), updatedAt (ISO 8601|null), workspaceName (string|null)
        Use for: linking to a user Doc. Tap navigates via \`navigate_document\`.
      </component>

      <component name="WeeklyAgendaCard">
        Props: weekStart (ISO 8601 date), days (array of 7 {date, eventCount, taskCount, label?}, required)
        Use for: high-level weekly density view. Each day cell shows event + task counts; tap fires \`navigate_day\` with {date}.
      </component>

      <component name="MetricCard">
        Props: label (string, required), value (string, required — pre-formatted), delta (string|null, e.g. "+12"), deltaDirection ("up"|"down"|"neutral"|null), helpText (string|null)
        Use for: a single headline stat like "47 unread", "3 meetings today", "Inbox zero in 2 days".
      </component>
    </utility_cards>

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
        Props: label (string), action (string), actionParams (object|null — each value must be a string; JSON.stringify nested data), variant ("default"|"outline"|"ghost"|"destructive"|null)
        Available actions: navigate_thread, navigate_task, navigate_event, archive_email, mark_read, mark_unread, complete_task, delete_task, update_draft, send_draft, attach_to_draft, copy_text, undo, open_attachment, toggle_checklist_item, navigate_document, navigate_day
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
    - When showing 2 or more items of the same type, use the corresponding *ListCard (TaskListCard, EmailListCard, CalendarEventListCard, ContactListCard) instead of repeating individual cards. The list cards adapt their layout automatically.
    - Use SearchResultCard as a header before listing email/task results.
    - Use InlineComposeCard (NOT DraftCard) when the user asks to compose, draft, or send a new email — the user must be able to send without leaving chat.
    - Use ActionConfirmationCard after completing a reversible mutation (archive, delete, mark-read, complete-task). Always populate undoAction/undoParams for reversible operations.
    - Use CopyableTextCard for any string the user is likely to copy (codes, snippets, generated text).
    - Use SuggestionsCard at most once per response, and only when there are 2-4 obvious follow-ups.
    - Limit lists to 10 items maximum (use a "Show more" SuggestionsCard chip if more exist).
    - Use cards for structured data. Use plain text for explanations and questions.
    - Do NOT use cards for simple yes/no answers or short text responses.
    - All date/time values must be ISO 8601 format.
    - The spec must be valid JSON — no trailing commas, no comments. Long body strings (e.g. InlineComposeCard.body) must escape quotes and newlines.
    - actionParams is an object map: each key is a parameter name and each value MUST be a plain string. When the model needs structured data, JSON.stringify the structure and store that single string as the value; the client parses string values that hold JSON when needed. (Same rule for InlineComposeCard field payloads and Button actionParams.)
  </rules>

  <intent_mapping>
    - User asks about unread/recent emails → EmailListCard (with summary if appropriate)
    - User searches for emails → SearchResultCard + EmailListCard
    - User asks about tasks/to-dos → TaskListCard (single item: TaskCard)
    - User creates tasks from email → TaskListCard
    - User asks about calendar/schedule → CalendarEventListCard
    - User asks about labels → LabelCard list (no LabelListCard yet)
    - User asks about a contact/sender → ContactListCard (single item: ContactCard)
    - User asks about drafts → DraftCard list (read-only)
    - User asks about notes → NoteCard list
    - User asks to compose/draft/send a new email → InlineComposeCard with a real draftId
    - User asks for text they'll copy (code, addresses, generated copy) → CopyableTextCard
    - Tool mutation just succeeded → ActionConfirmationCard (with undo when reversible)
    - There are 2-4 strong follow-up actions → end response with one SuggestionsCard
    - Quoting a specific email/document line → QuoteCard (with sourceAction=navigate_thread when applicable)
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

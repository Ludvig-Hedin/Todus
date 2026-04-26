/**
 * Generative UI Catalog — Single source of truth for all chat card types.
 *
 * This catalog defines the component vocabulary that the AI can use when
 * rendering rich cards in the chat interface. Both the React (web) renderer
 * and the SwiftUI (iOS) renderer implement the same set of components.
 *
 * To add a new card type:
 * 1. Add it here with a zod schema for its props.
 * 2. Implement the React component in ./components/<Name>.tsx
 * 3. Register it in ./registry.tsx
 * 4. Implement the SwiftUI view in the iOS app (ChatUISpec/).
 */

import { defineCatalog } from '@json-render/core';
import { schema } from '@json-render/react/schema';
import { z } from 'zod';

export const chatCatalog = defineCatalog(schema, {
  components: {
    // ─── Domain Cards ────────────────────────────────────────────

    EmailCard: {
      props: z.object({
        threadId: z.string().describe('The email thread ID, used for navigation'),
        sender: z.string().describe('Sender display name'),
        senderEmail: z.string().describe('Sender email address'),
        subject: z.string().describe('Email subject line'),
        snippet: z.string().describe('Short preview of the email body'),
        receivedAt: z.string().describe('ISO 8601 timestamp of when the email was received'),
        isUnread: z.boolean().nullable().describe('Whether the email is unread'),
        labels: z
          .array(z.object({ name: z.string(), color: z.string().nullable() }))
          .nullable()
          .describe('Labels applied to this thread'),
      }),
      description:
        'Displays a single email thread preview. Use when showing email search results, unread messages, or thread summaries.',
    },

    TaskCard: {
      props: z.object({
        taskId: z.string().describe('The task ID, used for navigation'),
        title: z.string().describe('Task title'),
        description: z.string().nullable().describe('Optional task description'),
        status: z
          .enum(['todo', 'doing', 'done'])
          .describe('Current task status'),
        priority: z
          .enum(['none', 'low', 'medium', 'high'])
          .describe('Task priority level'),
        dueDate: z.string().nullable().describe('ISO 8601 due date, or null if none'),
        folderName: z.string().nullable().describe('Name of the folder this task belongs to'),
        emailThreadId: z.string().nullable().describe('Linked email thread ID, if any'),
      }),
      description:
        'Displays a single task. Use when showing tasks, to-do items, or action items created from emails.',
    },

    CalendarEventCard: {
      props: z.object({
        eventId: z.string().describe('The calendar event ID'),
        title: z.string().describe('Event title'),
        start: z.string().describe('ISO 8601 start time'),
        end: z.string().describe('ISO 8601 end time'),
        location: z.string().nullable().describe('Event location, if any'),
        isAllDay: z.boolean().nullable().describe('Whether this is an all-day event'),
        attendees: z
          .array(z.object({ name: z.string().nullable(), email: z.string() }))
          .nullable()
          .describe('List of attendees'),
      }),
      description:
        'Displays a calendar event. Use when showing schedule, meetings, or upcoming events.',
    },

    NoteCard: {
      props: z.object({
        noteId: z.string().describe('The note ID'),
        content: z.string().describe('Note text content'),
        color: z.string().nullable().describe('Note color identifier'),
        isPinned: z.boolean().nullable().describe('Whether the note is pinned'),
        threadId: z.string().nullable().describe('The email thread this note is attached to'),
      }),
      description:
        'Displays a note attached to an email thread. Use when showing thread notes or annotations.',
    },

    DraftCard: {
      props: z.object({
        draftId: z.string().describe('The draft ID'),
        to: z
          .array(z.object({ name: z.string().nullable(), email: z.string() }))
          .nullable()
          .describe('Recipients'),
        subject: z.string().describe('Draft subject line'),
        snippet: z.string().describe('Preview of draft body'),
        updatedAt: z.string().nullable().describe('ISO 8601 last updated timestamp'),
      }),
      description:
        'Displays an email draft preview. Use when showing saved drafts or composed emails.',
    },

    LabelCard: {
      props: z.object({
        labelId: z.string().describe('The label ID'),
        name: z.string().describe('Label display name'),
        color: z.string().nullable().describe('Label color hex code'),
        count: z.number().nullable().describe('Number of threads with this label'),
      }),
      description:
        'Displays an email label. Use when listing labels, showing label management, or categorization results.',
    },

    ContactCard: {
      props: z.object({
        name: z.string().describe('Contact display name'),
        email: z.string().describe('Contact email address'),
        avatarUrl: z.string().nullable().describe('URL to the contact avatar image'),
      }),
      description:
        'Displays a contact or sender. Use when showing who sent an email or listing contacts.',
    },

    SearchResultCard: {
      props: z.object({
        query: z.string().describe('The search query that was executed'),
        resultCount: z.number().describe('Total number of results found'),
        summary: z.string().nullable().describe('Brief summary of results'),
      }),
      description:
        'Displays a search result summary header. Use before listing email/task results to show what was searched.',
    },

    // ─── List cards ──────────────────────────────────────────────

    TaskListCard: {
      props: z.object({
        title: z.string().nullable().describe('Optional heading shown above the list'),
        tasks: z
          .array(
            z.object({
              taskId: z.string(),
              title: z.string(),
              description: z.string().nullable(),
              status: z.enum(['todo', 'doing', 'done']),
              priority: z.enum(['none', 'low', 'medium', 'high']),
              dueDate: z.string().nullable(),
              folderName: z.string().nullable(),
              emailThreadId: z.string().nullable(),
            }),
          )
          .describe('Tasks to display'),
        followUp: z.string().nullable().describe('Optional follow-up question shown after the list'),
        groupedThreshold: z
          .number()
          .nullable()
          .describe('Render separated cards when tasks.length is below this number, otherwise group with separators (default 4)'),
      }),
      description:
        'Adaptive task list. Prefer over emitting multiple TaskCards. Renders separate rounded cards when below threshold, one grouped card with separators when at or above.',
    },

    EmailListCard: {
      props: z.object({
        title: z.string().nullable().describe('Optional heading'),
        emails: z
          .array(
            z.object({
              threadId: z.string(),
              sender: z.string(),
              senderEmail: z.string(),
              subject: z.string(),
              snippet: z.string(),
              receivedAt: z.string(),
              isUnread: z.boolean().nullable(),
              labels: z.array(z.object({ name: z.string(), color: z.string().nullable() })).nullable(),
            }),
          )
          .describe('Emails to display'),
        summary: z.string().nullable().describe('Optional AI-written summary block shown below the list'),
      }),
      description:
        'Email rows in a single grouped card with optional summary. Prefer over emitting multiple EmailCards.',
    },

    CalendarEventListCard: {
      props: z.object({
        title: z.string().nullable(),
        events: z
          .array(
            z.object({
              eventId: z.string(),
              title: z.string(),
              start: z.string(),
              end: z.string(),
              location: z.string().nullable(),
              isAllDay: z.boolean().nullable(),
              attendees: z
                .array(z.object({ name: z.string().nullable(), email: z.string() }))
                .nullable(),
            }),
          )
          .describe('Events to display'),
        summary: z.string().nullable().describe('Optional summary'),
      }),
      description: 'Event rows in a single grouped card.',
    },

    ContactListCard: {
      props: z.object({
        title: z.string().nullable(),
        contacts: z
          .array(
            z.object({
              name: z.string(),
              email: z.string(),
              avatarUrl: z.string().nullable(),
            }),
          )
          .describe('Contacts to display'),
      }),
      description: 'Contact rows in a single grouped card.',
    },

    // ─── Utility cards ───────────────────────────────────────────

    CopyableTextCard: {
      props: z.object({
        label: z.string().describe('Small grey header label (e.g. "text", "code", "address")'),
        content: z.string().describe('The text to display, with a copy button in the header'),
      }),
      description: 'Labeled text block with a copy-to-clipboard button. Use for any text the user might copy.',
    },

    InlineComposeCard: {
      props: z.object({
        draftId: z.string().describe('The draft ID for autosave + send (must come from drafts.create)'),
        to: z.array(z.object({ name: z.string().nullable(), email: z.string() })),
        cc: z.array(z.object({ name: z.string().nullable(), email: z.string() })).nullable(),
        bcc: z.array(z.object({ name: z.string().nullable(), email: z.string() })).nullable(),
        subject: z.string(),
        body: z.string(),
        attachments: z
          .array(z.object({ name: z.string(), size: z.number(), mimeType: z.string() }))
          .nullable(),
        status: z.enum(['draft', 'sending', 'sent', 'error']).nullable(),
      }),
      description:
        'Editable + sendable email draft inside chat. Uses local state for in-flight edits; debounced autosave via update_draft action; Send button triggers send_draft.',
    },

    SuggestionsCard: {
      props: z.object({
        suggestions: z
          .array(
            z.object({
              label: z.string(),
              action: z.string(),
              params: z.record(z.string()).nullable(),
            }),
          )
          .describe('Chip strip of follow-up actions'),
      }),
      description: 'Horizontal chip strip of suggested follow-up actions. Use sparingly — at most one per response.',
    },

    ActionConfirmationCard: {
      props: z.object({
        icon: z.string().nullable().describe('Optional icon name (e.g. "check", "archive", "trash")'),
        message: z.string().describe('Confirmation message (e.g. "Archived 5 emails")'),
        undoAction: z.string().nullable().describe('Action name to dispatch when undo is tapped'),
        undoParams: z
          .string()
          .nullable()
          .describe('JSON-encoded object string for undo params (same shape as the undo action expects after JSON.parse)'),
      }),
      description: 'Confirmation tile for completed mutations. Always include undo for reversible actions.',
    },

    QuoteCard: {
      props: z.object({
        quote: z.string().describe('The quoted text'),
        sourceLabel: z.string().nullable().describe('Optional citation (e.g. "Mark Johnson, Mar 12")'),
        sourceAction: z.string().nullable().describe('Optional action when the source is tapped'),
        sourceParams: z.record(z.string()).nullable().describe('Params for the source action'),
      }),
      description: 'Highlighted quote/excerpt with optional source citation.',
    },

    // ─── Round 2: domain-specific utility cards ──────────────────

    AttachmentCard: {
      props: z.object({
        name: z.string().describe('File name as shown to the user'),
        size: z.number().describe('File size in bytes'),
        mimeType: z.string().describe('MIME type, e.g. application/pdf, image/png'),
        previewUrl: z.string().nullable().describe('Optional signed URL for an inline thumbnail (image/* only)'),
        downloadAction: z.string().nullable().describe('Action to dispatch on tap (default: open_attachment)'),
        downloadParams: z.record(z.string()).nullable().describe('Params for the download action'),
      }),
      description: 'File attachment chip — shows icon by mime type, name, formatted size, and a tap-to-open affordance.',
    },

    CodeBlockCard: {
      props: z.object({
        language: z.string().describe('Programming language hint, e.g. "ts", "python", "swift"'),
        code: z.string().describe('Code body'),
        filename: z.string().nullable().describe('Optional filename label shown next to the language'),
      }),
      description: 'Syntax-aware code block with language label and copy button. Use over CopyableTextCard for code.',
    },

    ChecklistCard: {
      props: z.object({
        title: z.string().nullable(),
        items: z
          .array(
            z.object({
              id: z.string(),
              label: z.string(),
              done: z.boolean(),
            }),
          )
          .describe('Interactive checklist items'),
      }),
      description: 'Ad-hoc checklist the user can tick off in chat. Distinct from real tasks — tap fires toggle_checklist_item.',
    },

    DocumentCard: {
      props: z.object({
        documentId: z.string().describe('The document id used by navigate_document'),
        title: z.string(),
        snippet: z.string().nullable(),
        updatedAt: z.string().nullable().describe('ISO 8601 last updated'),
        workspaceName: z.string().nullable(),
      }),
      description: 'Reference to a user Doc with title, snippet, last edited, and tap-to-open.',
    },

    WeeklyAgendaCard: {
      props: z.object({
        weekStart: z.string().describe('ISO 8601 date for the Monday (or week-start) of the displayed week'),
        days: z
          .array(
            z.object({
              date: z.string().describe('ISO 8601 date'),
              eventCount: z.number(),
              taskCount: z.number(),
              label: z.string().nullable().describe('Optional override label, e.g. "Today"'),
            }),
          )
          .describe('Exactly 7 days, in chronological order'),
      }),
      description: 'Compact 7-day agenda density view. Each day cell shows event + task counts; tap fires navigate_day.',
    },

    MetricCard: {
      props: z.object({
        label: z.string().describe('e.g. "Unread"'),
        value: z.string().describe('Pre-formatted display value, e.g. "47"'),
        delta: z.string().nullable().describe('e.g. "+12" or "-3" — optional change indicator'),
        deltaDirection: z.enum(['up', 'down', 'neutral']).nullable(),
        helpText: z.string().nullable().describe('Optional sub-label, e.g. "since yesterday"'),
      }),
      description: 'Single headline stat tile with optional delta. Use for "X unread", "Y meetings today", etc.',
    },

    // ─── Layout & Utility Components ─────────────────────────────

    Stack: {
      props: z.object({
        direction: z.enum(['vertical', 'horizontal']).describe('Stack direction'),
        gap: z.enum(['none', 'sm', 'md', 'lg']).nullable().describe('Gap between children'),
        align: z
          .enum(['start', 'center', 'end', 'stretch'])
          .nullable()
          .describe('Cross-axis alignment'),
      }),
      slots: ['default'],
      description: 'Layout container that arranges children vertically or horizontally.',
    },

    Card: {
      props: z.object({
        title: z.string().nullable().describe('Optional card title'),
        description: z.string().nullable().describe('Optional card description'),
        padding: z.enum(['none', 'sm', 'md', 'lg']).nullable().describe('Inner padding'),
      }),
      slots: ['default'],
      description: 'Generic container card. Use for grouping related content.',
    },

    Text: {
      props: z.object({
        content: z.string().describe('Text content to display'),
        variant: z
          .enum(['heading', 'subheading', 'body', 'caption', 'code'])
          .nullable()
          .describe('Text style variant'),
      }),
      description: 'Inline text element with optional styling variant.',
    },

    Button: {
      props: z.object({
        label: z.string().describe('Button label text'),
        action: z
          .string()
          .describe('Action identifier to execute when pressed (e.g. navigate_thread, archive_email)'),
        actionParams: z.record(z.string()).nullable().describe('Optional parameters for the action'),
        variant: z
          .enum(['default', 'outline', 'ghost', 'destructive'])
          .nullable()
          .describe('Button visual variant'),
      }),
      description: 'Clickable button that triggers an action.',
    },

    Badge: {
      props: z.object({
        label: z.string().describe('Badge text'),
        variant: z
          .enum(['default', 'success', 'warning', 'destructive', 'outline'])
          .nullable()
          .describe('Badge visual variant'),
      }),
      description: 'Small status indicator or label.',
    },

    Divider: {
      props: z.object({}),
      description: 'Visual separator between content sections.',
    },
  },

  actions: {
    navigate_thread: {
      params: z.object({ threadId: z.string() }),
      description: 'Navigate to an email thread view',
    },
    navigate_task: {
      params: z.object({ taskId: z.string() }),
      description: 'Open a task detail sheet',
    },
    navigate_event: {
      params: z.object({ eventId: z.string() }),
      description: 'Open a calendar event detail',
    },
    archive_email: {
      params: z.object({ threadIds: z.array(z.string()) }),
      description: 'Archive one or more email threads',
    },
    mark_read: {
      params: z.object({ threadIds: z.array(z.string()) }),
      description: 'Mark threads as read',
    },
    mark_unread: {
      params: z.object({ threadIds: z.array(z.string()) }),
      description: 'Mark threads as unread',
    },
    complete_task: {
      params: z.object({ taskId: z.string() }),
      description: 'Mark a task as done',
    },
    delete_task: {
      params: z.object({ taskId: z.string() }),
      description: 'Delete a task',
    },
    // Note: payload is a JSON-encoded string carrying nested fields (recipients, etc.).
    // The action signature must stay flat strings to remain compatible with the iOS/macOS
    // (action: String, params: [String: String]) callback contract.
    update_draft: {
      params: z.object({ draftId: z.string(), payload: z.string() }),
      description: 'Autosave changes to a draft (debounced inside the InlineComposeCard)',
    },
    send_draft: {
      params: z.object({ draftId: z.string(), payload: z.string() }),
      description: 'Send the draft, including any unsynced field changes from the card',
    },
    attach_to_draft: {
      params: z.object({ draftId: z.string() }),
      description: 'Open the platform-native attachment picker for the draft',
    },
    copy_text: {
      params: z.object({ content: z.string() }),
      description: 'Copy text to the system clipboard',
    },
    undo: {
      params: z.object({ undoAction: z.string(), undoParams: z.string() }),
      description: 'Re-dispatch the inverse of a previously confirmed action',
    },
    open_attachment: {
      params: z.object({ name: z.string(), mimeType: z.string(), previewUrl: z.string().optional() }),
      description: 'Open or download an attachment from an AttachmentCard',
    },
    toggle_checklist_item: {
      params: z.object({ id: z.string(), done: z.string() }),
      description: 'Toggle a single ChecklistCard item (done is "true" or "false")',
    },
    navigate_document: {
      params: z.object({ documentId: z.string() }),
      description: 'Open a user Doc',
    },
    navigate_day: {
      params: z.object({ date: z.string() }),
      description: 'Open the calendar focused on a specific day',
    },
  },
});

/**
 * Generates the system prompt fragment for the AI to use the catalog.
 * Pass this to the AI's system prompt alongside other instructions.
 */
export function getChatCatalogPrompt(customRules?: string[]): string {
  return chatCatalog.prompt({
    customRules: [
      'Always use Stack with direction=vertical as the root element when showing multiple cards.',
      'When showing 2+ items of the same type, use the matching list card (TaskListCard, EmailListCard, CalendarEventListCard, ContactListCard) rather than emitting individual cards in a Stack.',
      'Use EmailCard for a single email thread result. Always include threadId for navigation.',
      'Use TaskCard for a single task. Always include taskId.',
      'Use CalendarEventCard for a single event.',
      'Use SearchResultCard as a header before listing results.',
      'Use InlineComposeCard (NOT DraftCard) when the user wants to compose, draft, or send a new email — they must be able to send it from chat.',
      'Use ActionConfirmationCard after a tool mutation succeeds. Include undoAction and undoParams as a JSON **string** (stringify the params object) for reversible operations.',
      'Use CopyableTextCard for any text the user is likely to copy (codes, snippets, generated copy).',
      'Use SuggestionsCard at most once per response.',
      'Keep card lists to a maximum of 10 items to avoid overwhelming the user.',
      'Use Badge to highlight status (e.g. unread, high priority, overdue).',
      'Use Button for actionable operations like archive, mark read, complete task.',
      ...(customRules ?? []),
    ],
  });
}

/** TypeScript type for a full UI spec produced by the AI */
export type ChatUISpec = {
  root: string;
  elements: Record<
    string,
    {
      type: string;
      props: Record<string, unknown>;
      children?: string[];
    }
  >;
};

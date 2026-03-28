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
      'Use EmailCard for email thread results. Always include threadId for navigation.',
      'Use TaskCard for tasks and action items. Always include taskId.',
      'Use CalendarEventCard for schedule and meeting queries.',
      'Use SearchResultCard as a header before listing results.',
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

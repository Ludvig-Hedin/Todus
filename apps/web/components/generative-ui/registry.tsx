/**
 * json-render Registry — Maps catalog component types to React implementations.
 *
 * This file connects the abstract catalog (zod schemas) to concrete React
 * components. The Renderer uses this registry to look up how to render
 * each element in a UI spec.
 */

import { defineRegistry } from '@json-render/react';
import { chatCatalog } from './catalog';
import { useQueryState } from 'nuqs';
import { useCallback } from 'react';

// Domain card components
import { EmailCard } from './components/EmailCard';
import { TaskCard } from './components/TaskCard';
import { CalendarEventCard } from './components/CalendarEventCard';
import { NoteCard } from './components/NoteCard';
import { DraftCard } from './components/DraftCard';
import { LabelCard } from './components/LabelCard';
import { ContactCard } from './components/ContactCard';
import { SearchResultCard } from './components/SearchResultCard';

// List + utility cards
import { TaskListCard } from './components/TaskListCard';
import { EmailListCard } from './components/EmailListCard';
import { CalendarEventListCard } from './components/CalendarEventListCard';
import { ContactListCard } from './components/ContactListCard';
import { CopyableTextCard } from './components/CopyableTextCard';
import { InlineComposeCard } from './components/InlineComposeCard';
import { SuggestionsCard } from './components/SuggestionsCard';
import { ActionConfirmationCard } from './components/ActionConfirmationCard';
import { QuoteCard } from './components/QuoteCard';

// Round 2 cards
import { AttachmentCard } from './components/AttachmentCard';
import { CodeBlockCard } from './components/CodeBlockCard';
import { ChecklistCard } from './components/ChecklistCard';
import { DocumentCard } from './components/DocumentCard';
import { WeeklyAgendaCard } from './components/WeeklyAgendaCard';
import { MetricCard } from './components/MetricCard';

// Layout components
import {
  StackComponent,
  CardComponent,
  TextComponent,
  ButtonComponent,
  BadgeComponent,
  DividerComponent,
} from './components/layout';

// tRPC client for draft mutations
import { useTRPC } from '@/providers/query-provider';
import { useMutation } from '@tanstack/react-query';
import { toast } from 'sonner';

export const { registry, handlers, executeAction } = defineRegistry(chatCatalog, {
  components: {
    // Domain cards — each receives typed props from the catalog
    EmailCard: ({ props, emit }) => <EmailCard props={props} emit={emit} />,
    TaskCard: ({ props, emit }) => <TaskCard props={props} emit={emit} />,
    CalendarEventCard: ({ props, emit }) => <CalendarEventCard props={props} emit={emit} />,
    NoteCard: ({ props, emit }) => <NoteCard props={props} emit={emit} />,
    DraftCard: ({ props, emit }) => <DraftCard props={props} emit={emit} />,
    LabelCard: ({ props }) => <LabelCard props={props} />,
    ContactCard: ({ props }) => <ContactCard props={props} />,
    SearchResultCard: ({ props }) => <SearchResultCard props={props} />,

    // List + utility cards
    TaskListCard: ({ props, emit }) => <TaskListCard props={props} emit={emit} />,
    EmailListCard: ({ props, emit }) => <EmailListCard props={props} emit={emit} />,
    CalendarEventListCard: ({ props, emit }) => <CalendarEventListCard props={props} emit={emit} />,
    ContactListCard: ({ props }) => <ContactListCard props={props} />,
    CopyableTextCard: ({ props, emit }) => <CopyableTextCard props={props} emit={emit} />,
    InlineComposeCard: ({ props, emit }) => <InlineComposeCard props={props} emit={emit} />,
    SuggestionsCard: ({ props, emit }) => <SuggestionsCard props={props} emit={emit} />,
    ActionConfirmationCard: ({ props, emit }) => <ActionConfirmationCard props={props} emit={emit} />,
    QuoteCard: ({ props, emit }) => <QuoteCard props={props} emit={emit} />,

    // Round 2
    AttachmentCard: ({ props, emit }) => <AttachmentCard props={props} emit={emit} />,
    CodeBlockCard: ({ props, emit }) => <CodeBlockCard props={props} emit={emit} />,
    ChecklistCard: ({ props, emit }) => <ChecklistCard props={props} emit={emit} />,
    DocumentCard: ({ props, emit }) => <DocumentCard props={props} emit={emit} />,
    WeeklyAgendaCard: ({ props, emit }) => <WeeklyAgendaCard props={props} emit={emit} />,
    MetricCard: ({ props }) => <MetricCard props={props} />,

    // Layout components
    Stack: ({ props, children }) => <StackComponent props={props}>{children}</StackComponent>,
    Card: ({ props, children }) => <CardComponent props={props}>{children}</CardComponent>,
    Text: ({ props }) => <TextComponent props={props} />,
    Button: ({ props, emit }) => <ButtonComponent props={props} emit={emit} />,
    Badge: ({ props }) => <BadgeComponent props={props} />,
    Divider: () => <DividerComponent />,
  },

  actions: {
    // The runtime handlers below are stubs; the real wiring lives in `useCardActions`
    // (which has access to React hooks, navigation, and the tRPC client).
    navigate_thread: async (params) => console.log('[generative-ui] navigate_thread', params),
    navigate_task: async (params) => console.log('[generative-ui] navigate_task', params),
    navigate_event: async (params) => console.log('[generative-ui] navigate_event', params),
    archive_email: async (params) => console.log('[generative-ui] archive_email', params),
    mark_read: async (params) => console.log('[generative-ui] mark_read', params),
    mark_unread: async (params) => console.log('[generative-ui] mark_unread', params),
    complete_task: async (params) => console.log('[generative-ui] complete_task', params),
    delete_task: async (params) => console.log('[generative-ui] delete_task', params),
    update_draft: async (params) => console.log('[generative-ui] update_draft', params),
    send_draft: async (params) => console.log('[generative-ui] send_draft', params),
    attach_to_draft: async (params) => console.log('[generative-ui] attach_to_draft', params),
    copy_text: async (params) => console.log('[generative-ui] copy_text', params),
    undo: async (params) => console.log('[generative-ui] undo', params),
    open_attachment: async (params) => console.log('[generative-ui] open_attachment', params),
    toggle_checklist_item: async (params) => console.log('[generative-ui] toggle_checklist_item', params),
    navigate_document: async (params) => console.log('[generative-ui] navigate_document', params),
    navigate_day: async (params) => console.log('[generative-ui] navigate_day', params),
  },
});

/**
 * Hook that creates action handlers connected to the app's navigation and tRPC mutations.
 * Use this in the chat component to handle card interactions.
 */
export function useCardActions() {
  const [, setThreadId] = useQueryState('threadId');
  const [, setIsFullScreen] = useQueryState('isFullScreen');
  const trpc = useTRPC();
  const { mutateAsync: updateDraft } = useMutation(trpc.drafts.update.mutationOptions());
  const { mutateAsync: sendEmail } = useMutation(trpc.mail.send.mutationOptions());

  const handleCardAction = useCallback(
    (action: string, params: Record<string, unknown>) => {
      switch (action) {
        case 'navigate_thread':
          if (params.threadId) {
            setThreadId(params.threadId as string);
            setIsFullScreen(null);
          }
          break;
        case 'navigate_task':
          console.log('[generative-ui] navigate to task', params.taskId);
          break;
        case 'navigate_event':
          console.log('[generative-ui] navigate to event', params.eventId);
          break;
        case 'navigate_draft':
          console.log('[generative-ui] navigate to draft', params.draftId);
          break;
        case 'copy_text':
          if (typeof params.content === 'string' && typeof navigator !== 'undefined') {
            void navigator.clipboard?.writeText(params.content);
          }
          break;
        case 'update_draft': {
          const draftId = params.draftId as string | undefined;
          const payload = params.payload as string | undefined;
          if (!draftId || !payload) break;
          try {
            const fields = JSON.parse(payload) as {
              to: Array<{ name: string | null; email: string }>;
              cc: Array<{ name: string | null; email: string }>;
              bcc: Array<{ name: string | null; email: string }>;
              subject: string;
              body: string;
            };
            const isRecipient = (value: unknown): value is { name: string | null; email: string } =>
              typeof value === 'object' &&
              value !== null &&
              typeof (value as { email?: unknown }).email === 'string' &&
              ('name' in (value as Record<string, unknown>)
                ? typeof (value as { name?: unknown }).name === 'string' ||
                  (value as { name?: unknown }).name === null
                : true);
            if (
              typeof fields !== 'object' ||
              fields === null ||
              !Array.isArray(fields.to) ||
              !Array.isArray(fields.cc) ||
              !Array.isArray(fields.bcc) ||
              !fields.to.every(isRecipient) ||
              !fields.cc.every(isRecipient) ||
              !fields.bcc.every(isRecipient) ||
              typeof fields.subject !== 'string' ||
              typeof fields.body !== 'string'
            ) {
              throw new Error('Invalid payload structure');
            }
            const fmt = (r: { name: string | null; email: string }) =>
              r.name ? `${r.name} <${r.email}>` : r.email;
            void updateDraft({
              id: draftId,
              to: fields.to.map(fmt).join(', '),
              cc: fields.cc.length ? fields.cc.map(fmt).join(', ') : undefined,
              bcc: fields.bcc.length ? fields.bcc.map(fmt).join(', ') : undefined,
              subject: fields.subject,
              message: fields.body,
              threadId: null,
              fromEmail: null,
            }).catch((err) => {
              console.error('[generative-ui] update_draft failed', err);
              toast.error('Could not save draft.');
            });
          } catch (err) {
            console.warn('[generative-ui] update_draft payload parse failed', err);
            toast.error('Could not save draft.');
          }
          break;
        }
        case 'send_draft': {
          const draftId = params.draftId as string | undefined;
          const payload = params.payload as string | undefined;
          if (!payload) break;
          try {
            const fields = JSON.parse(payload) as {
              to: Array<{ name: string | null; email: string }>;
              cc: Array<{ name: string | null; email: string }>;
              bcc: Array<{ name: string | null; email: string }>;
              subject: string;
              body: string;
            };
            void sendEmail({
              to: fields.to.map((r) => ({ name: r.name ?? undefined, email: r.email })),
              cc: fields.cc.length
                ? fields.cc.map((r) => ({ name: r.name ?? undefined, email: r.email }))
                : undefined,
              bcc: fields.bcc.length
                ? fields.bcc.map((r) => ({ name: r.name ?? undefined, email: r.email }))
                : undefined,
              subject: fields.subject,
              message: fields.body,
              draftId,
            })
              .then(() => toast.success('Email sent'))
              .catch((err) => {
                console.error('[generative-ui] send_draft failed', err);
                toast.error('Could not send email.');
              });
          } catch (err) {
            console.warn('[generative-ui] send_draft payload parse failed', err);
            toast.error('Could not send email.');
          }
          break;
        }
        case 'attach_to_draft':
          // Trigger the user's file picker. Implementation hooks into the existing compose
          // attach flow once an InlineComposeCard surface is selected.
          console.log('[generative-ui] attach_to_draft', params.draftId);
          break;
        case 'undo': {
          const undoAction = params.undoAction as string | undefined;
          const undoParamsStr = params.undoParams as string | undefined;
          const rawDepth = params._undoDepth;
          const depth =
            typeof rawDepth === 'number' && Number.isFinite(rawDepth) ? rawDepth : 0;
          if (depth > 8) {
            console.warn('[generative-ui] undo depth limit exceeded');
            toast.error('Unable to undo: too many nested steps.');
            break;
          }
          if (!undoAction || undoAction === 'undo') break;
          let undoParams: Record<string, unknown> = {};
          if (undoParamsStr) {
            try {
              undoParams = JSON.parse(undoParamsStr) as Record<string, unknown>;
            } catch {
              undoParams = {};
            }
          }
          handleCardAction(undoAction, { ...undoParams, _undoDepth: depth + 1 });
          break;
        }
        case 'open_attachment': {
          const previewUrl = params.previewUrl as string | undefined;
          if (previewUrl && typeof window !== 'undefined') {
            // Open the preview/download in a new tab — consistent with how attachments
            // open from the inbox today.
            window.open(previewUrl, '_blank', 'noopener,noreferrer');
          } else {
            console.log('[generative-ui] open_attachment (no preview)', params);
          }
          break;
        }
        case 'toggle_checklist_item':
          // Local-only state lives inside the ChecklistCard. Server persistence would land here
          // once a checklist persistence model exists; we just log the intent for now.
          console.log('[generative-ui] toggle_checklist_item', params);
          break;
        case 'navigate_document':
          if (typeof params.documentId === 'string' && typeof window !== 'undefined') {
            window.location.href = `/docs/${encodeURIComponent(params.documentId)}`;
          }
          break;
        case 'navigate_day':
          if (typeof params.date === 'string' && typeof window !== 'undefined') {
            window.location.href = `/calendar?date=${encodeURIComponent(params.date)}`;
          }
          break;
        default:
          console.warn('[generative-ui] unknown action:', action, params);
      }
    },
    [setThreadId, setIsFullScreen, updateDraft, sendEmail],
  );

  return { handleCardAction };
}

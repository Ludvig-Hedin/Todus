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

// Layout components
import {
  StackComponent,
  CardComponent,
  TextComponent,
  ButtonComponent,
  BadgeComponent,
  DividerComponent,
} from './components/layout';

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

    // Layout components
    Stack: ({ props, children }) => <StackComponent props={props}>{children}</StackComponent>,
    Card: ({ props, children }) => <CardComponent props={props}>{children}</CardComponent>,
    Text: ({ props }) => <TextComponent props={props} />,
    Button: ({ props, emit }) => <ButtonComponent props={props} emit={emit} />,
    Badge: ({ props }) => <BadgeComponent props={props} />,
    Divider: () => <DividerComponent />,
  },

  actions: {
    navigate_thread: async (params) => {
      // Action dispatched — the ChatSpecRenderer hook handles navigation
      console.log('[generative-ui] navigate_thread', params);
    },
    navigate_task: async (params) => {
      console.log('[generative-ui] navigate_task', params);
    },
    navigate_event: async (params) => {
      console.log('[generative-ui] navigate_event', params);
    },
    archive_email: async (params) => {
      console.log('[generative-ui] archive_email', params);
    },
    mark_read: async (params) => {
      console.log('[generative-ui] mark_read', params);
    },
    mark_unread: async (params) => {
      console.log('[generative-ui] mark_unread', params);
    },
    complete_task: async (params) => {
      console.log('[generative-ui] complete_task', params);
    },
    delete_task: async (params) => {
      console.log('[generative-ui] delete_task', params);
    },
  },
});

/**
 * Hook that creates action handlers connected to the app's navigation.
 * Use this in the chat component to handle card interactions.
 */
export function useCardActions() {
  const [, setThreadId] = useQueryState('threadId');
  const [, setIsFullScreen] = useQueryState('isFullScreen');

  const handleCardAction = useCallback(
    (action: string, params: Record<string, unknown>) => {
      switch (action) {
        case 'navigate_thread':
          if (params.threadId) {
            setThreadId(params.threadId as string);
            setIsFullScreen(null); // Exit fullscreen to show thread
          }
          break;
        case 'navigate_task':
          // Task navigation — could open a sheet or navigate
          console.log('[generative-ui] navigate to task', params.taskId);
          break;
        case 'navigate_event':
          console.log('[generative-ui] navigate to event', params.eventId);
          break;
        case 'navigate_draft':
          console.log('[generative-ui] navigate to draft', params.draftId);
          break;
        default:
          console.warn('[generative-ui] unknown action:', action, params);
      }
    },
    [setThreadId, setIsFullScreen],
  );

  return { handleCardAction };
}

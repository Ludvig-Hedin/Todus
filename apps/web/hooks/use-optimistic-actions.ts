import { addOptimisticActionAtom, removeOptimisticActionAtom } from '@/store/optimistic-updates';
import { optimisticActionsManager, type PendingAction } from '@/lib/optimistic-actions-manager';
import { useMutation, useQueryClient, type InfiniteData } from '@tanstack/react-query';

import { backgroundQueueAtom } from '@/store/backgroundQueue';
import type { ThreadDestination } from '@/lib/thread-actions';
import { useTRPC } from '@/providers/query-provider';
import { useMail } from '@/components/mail/use-mail';
import { moveThreadsTo } from '@/lib/thread-actions';
import { m } from '@/paraglide/messages';
import { useQueryState } from 'nuqs';
import { useCallback } from 'react';
import posthog from 'posthog-js';
import { useAtom } from 'jotai';
import { toast } from 'sonner';

type ThreadSummary = {
  id: string;
  hasUnread?: boolean;
  isStarred?: boolean;
  isImportant?: boolean;
  labelIds?: string[];
};

type ThreadDetail = {
  hasUnread: boolean;
  labels: { id: string; name: string }[];
  latest?: {
    unread: boolean;
    tags: { id: string; name: string; type: string }[];
  };
};

enum ActionType {
  MOVE = 'MOVE',
  STAR = 'STAR',
  READ = 'READ',
  LABEL = 'LABEL',
  IMPORTANT = 'IMPORTANT',
  SNOOZE = 'SNOOZE',
  UNSNOOZE = 'UNSNOOZE',
  DELETE_DRAFT = 'DELETE_DRAFT',
}

// Update the params interface
interface ActionParams {
  starred?: boolean;
  read?: boolean;
  important?: boolean;
  labelId?: string;
  add?: boolean;
  currentFolder?: string;
  destination?: ThreadDestination;
  wakeAt?: string;
}

type ThreadListPage = {
  threads: ThreadSummary[];
  nextPageToken: string | null;
};

const actionEventNames: Record<ActionType, (params: ActionParams) => string> = {
  [ActionType.MOVE]: () => 'email_moved',
  [ActionType.STAR]: (params) => (params.starred ? 'email_starred' : 'email_unstarred'),
  [ActionType.READ]: (params) => (params.read ? 'email_marked_read' : 'email_marked_unread'),
  [ActionType.IMPORTANT]: (params) =>
    params.important ? 'email_marked_important' : 'email_unmarked_important',
  [ActionType.LABEL]: (params) => (params.add ? 'email_label_added' : 'email_label_removed'),
  [ActionType.SNOOZE]: () => 'email_snoozed',
  [ActionType.UNSNOOZE]: () => 'email_unsnoozed',
  [ActionType.DELETE_DRAFT]: () => 'draft_deleted',
};

export function useOptimisticActions() {
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const [, setBackgroundQueue] = useAtom(backgroundQueueAtom);
  const [, addOptimisticAction] = useAtom(addOptimisticActionAtom);
  const [, removeOptimisticAction] = useAtom(removeOptimisticActionAtom);
  const [threadId, setThreadId] = useQueryState('threadId');
  const [, setActiveReplyId] = useQueryState('activeReplyId');
  const [mail, setMail] = useMail();
  const { mutateAsync: markAsRead } = useMutation(trpc.mail.markAsRead.mutationOptions());
  const { mutateAsync: markAsUnread } = useMutation(trpc.mail.markAsUnread.mutationOptions());

  const { mutateAsync: toggleStar } = useMutation(trpc.mail.toggleStar.mutationOptions());
  const { mutateAsync: toggleImportant } = useMutation(trpc.mail.toggleImportant.mutationOptions());

  const { mutateAsync: bulkDeleteThread } = useMutation(trpc.mail.bulkDelete.mutationOptions());
  const { mutateAsync: snoozeThreads } = useMutation(trpc.mail.snoozeThreads.mutationOptions());
  const { mutateAsync: unsnoozeThreads } = useMutation(trpc.mail.unsnoozeThreads.mutationOptions());
  const { mutateAsync: modifyLabels } = useMutation(trpc.mail.modifyLabels.mutationOptions());

  const { mutateAsync: deleteDraft } = useMutation(trpc.drafts.delete.mutationOptions());

  const updateThreadSummaries = useCallback(
    (threadIds: string[], updater: (thread: ThreadSummary) => ThreadSummary) => {
      queryClient.setQueriesData(
        {
          predicate: (query) => {
            const [routeKey, queryMeta] = query.queryKey as [unknown, { type?: string }?];
            return (
              Array.isArray(routeKey) &&
              routeKey[0] === 'mail' &&
              routeKey[1] === 'listThreads' &&
              queryMeta?.type === 'infinite'
            );
          },
        },
        (data: InfiniteData<ThreadListPage> | undefined) => {
          if (!data) return data;

          return {
            ...data,
            pages: data.pages.map((page) => ({
              ...page,
              threads: page.threads.map((thread) =>
                threadIds.includes(thread.id) ? updater(thread) : thread,
              ),
            })),
          };
        },
      );
    },
    [queryClient],
  );

  const updateThreadDetails = useCallback(
    (threadIds: string[], updater: (thread: ThreadDetail) => ThreadDetail) => {
      threadIds.forEach((threadId) => {
        queryClient.setQueryData<ThreadDetail>(
          trpc.mail.get.queryKey({ id: threadId }),
          (current: ThreadDetail | undefined) => (current ? updater(current) : current),
        );
      });
    },
    [queryClient, trpc],
  );

  const applyReadPatch = useCallback(
    (threadIds: string[], read: boolean) => {
      updateThreadSummaries(threadIds, (thread) => ({
        ...thread,
        hasUnread: !read,
      }));

      updateThreadDetails(threadIds, (thread) => ({
        ...thread,
        hasUnread: !read,
        labels: read
          ? thread.labels.filter((label: { id: string; name: string }) => label.id !== 'UNREAD')
          : thread.labels.some((label: { id: string; name: string }) => label.id === 'UNREAD')
            ? thread.labels
            : [...thread.labels, { id: 'UNREAD', name: 'UNREAD' }],
        latest: thread.latest
          ? {
              ...thread.latest,
              unread: !read,
              tags: read
                ? thread.latest.tags.filter(
                    (tag: { id: string; name: string; type: string }) => tag.id !== 'UNREAD',
                  )
                : thread.latest.tags.some(
                    (tag: { id: string; name: string; type: string }) => tag.id === 'UNREAD',
                  )
                  ? thread.latest.tags
                  : [...thread.latest.tags, { id: 'UNREAD', name: 'UNREAD', type: 'system' }],
            }
          : thread.latest,
      }));
    },
    [updateThreadDetails, updateThreadSummaries],
  );

  const applyTagTogglePatch = useCallback(
    (threadIds: string[], tagId: 'STARRED' | 'IMPORTANT', enabled: boolean) => {
      const summaryField = tagId === 'STARRED' ? 'isStarred' : 'isImportant';

      updateThreadSummaries(threadIds, (thread) => ({
        ...thread,
        [summaryField]: enabled,
      }));

      updateThreadDetails(threadIds, (thread) => {
        const nextLabels = enabled
          ? thread.labels.some((label: { id: string; name: string }) => label.id === tagId)
            ? thread.labels
            : [...thread.labels, { id: tagId, name: tagId }]
          : thread.labels.filter((label: { id: string; name: string }) => label.id !== tagId);

        const nextTags = thread.latest
          ? enabled
            ? thread.latest.tags.some(
                (tag: { id: string; name: string; type: string }) => tag.id === tagId,
              )
              ? thread.latest.tags
              : [...thread.latest.tags, { id: tagId, name: tagId, type: 'system' }]
            : thread.latest.tags.filter(
                (tag: { id: string; name: string; type: string }) => tag.id !== tagId,
              )
          : undefined;

        return {
          ...thread,
          labels: nextLabels,
          latest: thread.latest
            ? {
                ...thread.latest,
                tags: nextTags ?? thread.latest.tags,
              }
            : thread.latest,
        };
      });
    },
    [updateThreadDetails, updateThreadSummaries],
  );

  const applyLabelPatch = useCallback(
    (threadIds: string[], labelId: string, add: boolean) => {
      updateThreadSummaries(threadIds, (thread) => {
        const labelIds = add
          ? thread.labelIds?.includes(labelId)
            ? thread.labelIds
            : [...(thread.labelIds ?? []), labelId]
          : (thread.labelIds ?? []).filter((currentLabelId: string) => currentLabelId !== labelId);

        return {
          ...thread,
          labelIds,
        };
      });

      updateThreadDetails(threadIds, (thread) => ({
        ...thread,
        labels: add
          ? thread.labels.some((label: { id: string; name: string }) => label.id === labelId)
            ? thread.labels
            : [...thread.labels, { id: labelId, name: labelId }]
          : thread.labels.filter((label: { id: string; name: string }) => label.id !== labelId),
      }));
    },
    [updateThreadDetails, updateThreadSummaries],
  );

  const generatePendingActionId = () =>
    `pending_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;

  const refreshData = useCallback(async () => {
    return await queryClient.refetchQueries({ queryKey: trpc.labels.list.queryKey() });
  }, [queryClient]);

  function createPendingAction({
    type,
    threadIds,
    params,
    optimisticId,
    execute,
    undo,
    toastMessage,
  }: {
    type: keyof typeof ActionType;
    threadIds: string[];
    params: PendingAction['params'];
    optimisticId: string;
    execute: () => Promise<void>;
    undo: () => void;
    toastMessage: string;
    folders?: string[];
  }) {
    const pendingActionId = generatePendingActionId();
    optimisticActionsManager.lastActionId = pendingActionId;
    console.log('here Generated pending action ID:', pendingActionId);

    if (!optimisticActionsManager.pendingActionsByType.has(type)) {
      console.log('here Creating new Set for action type:', type);
      optimisticActionsManager.pendingActionsByType.set(type, new Set());
    }
    optimisticActionsManager.pendingActionsByType.get(type)?.add(pendingActionId);
    console.log(
      'here',
      'Added pending action to type:',
      type,
      'Current size:',
      optimisticActionsManager.pendingActionsByType.get(type)?.size,
    );

    const pendingAction = {
      id: pendingActionId,
      type,
      threadIds,
      params,
      optimisticId,
      execute,
      undo,
    };

    optimisticActionsManager.pendingActions.set(pendingActionId, pendingAction as PendingAction);

    const itemCount = threadIds.length;
    const bulkActionMessage = itemCount > 1 ? `${toastMessage} (${itemCount} items)` : toastMessage;

    async function doAction() {
      try {
        await execute();
        const typeActions = optimisticActionsManager.pendingActionsByType.get(type);
        console.log('here', {
          pendingActionsByTypeRef: optimisticActionsManager.pendingActionsByType.get(type)?.size,
          pendingActionsRef: optimisticActionsManager.pendingActions.size,
          typeActions: typeActions?.size,
        });

        const eventName = actionEventNames[type]?.(params);
        if (eventName) {
          posthog.capture(eventName);
        }

        optimisticActionsManager.pendingActions.delete(pendingActionId);
        optimisticActionsManager.pendingActionsByType.get(type)?.delete(pendingActionId);
        if (typeActions?.size === 1) {
          await refreshData();
          removeOptimisticAction(optimisticId);
        }
      } catch (error) {
        console.error('Action failed:', error);
        removeOptimisticAction(optimisticId);
        optimisticActionsManager.pendingActions.delete(pendingActionId);
        optimisticActionsManager.pendingActionsByType.get(type)?.delete(pendingActionId);
        toast.error('Action failed');
      }
    }

    if (toastMessage.trim().length) {
      toast(bulkActionMessage, {
        onAutoClose: () => {
          doAction();
        },
        onDismiss: () => {
          doAction();
        },
        action: {
          label: 'Undo',
          onClick: () => {
            undo();
            optimisticActionsManager.pendingActions.delete(pendingActionId);
            optimisticActionsManager.pendingActionsByType.get(type)?.delete(pendingActionId);
          },
        },
        duration: 5000,
      });
    } else {
      doAction();
    }

    return pendingActionId;
  }

  const optimisticMarkAsRead = useCallback(
    (threadIds: string[], silent = false) => {
      if (!threadIds.length) return;

      const optimisticId = addOptimisticAction({
        type: 'READ',
        threadIds,
        read: true,
      });

      createPendingAction({
        type: 'READ',
        threadIds,
        params: { read: true },
        optimisticId,
        execute: async () => {
          await markAsRead({ ids: threadIds });
          applyReadPatch(threadIds, true);

          if (mail.bulkSelected.length > 0) {
            setMail((prev) => ({ ...prev, bulkSelected: [] }));
          }
        },
        undo: () => {
          removeOptimisticAction(optimisticId);
        },
        toastMessage: silent ? '' : 'Marked as read',
      });
    },
    [addOptimisticAction, applyReadPatch, markAsRead, mail.bulkSelected.length, removeOptimisticAction, setMail],
  );

  function optimisticMarkAsUnread(threadIds: string[]) {
    if (!threadIds.length) return;

    const optimisticId = addOptimisticAction({
      type: 'READ',
      threadIds,
      read: false,
    });

    createPendingAction({
      type: 'READ',
      threadIds,
      params: { read: false },
      optimisticId,
      execute: async () => {
        await markAsUnread({ ids: threadIds });
        applyReadPatch(threadIds, false);

        if (mail.bulkSelected.length > 0) {
          setMail({ ...mail, bulkSelected: [] });
        }
      },
      undo: () => {
        removeOptimisticAction(optimisticId);
      },
      toastMessage: 'Marked as unread',
    });
  }

  const optimisticToggleStar = useCallback(
    (threadIds: string[], starred: boolean) => {
      if (!threadIds.length) return;

      const optimisticId = addOptimisticAction({
        type: 'STAR',
        threadIds,
        starred,
      });

      createPendingAction({
        type: 'STAR',
        threadIds,
        params: { starred },
        optimisticId,
        execute: async () => {
          await toggleStar({ ids: threadIds });
          applyTagTogglePatch(threadIds, 'STARRED', starred);
        },
        undo: () => {
          removeOptimisticAction(optimisticId);
        },
        toastMessage: starred
          ? m['common.actions.addedToFavorites']()
          : m['common.actions.removedFromFavorites'](),
      });
    },
    [addOptimisticAction, applyTagTogglePatch, removeOptimisticAction, toggleStar],
  );

  function optimisticMoveThreadsTo(
    threadIds: string[],
    currentFolder: string,
    destination: ThreadDestination,
  ) {
    if (!threadIds.length || !destination) return;

    // setFocusedIndex(null);

    const optimisticId = addOptimisticAction({
      type: 'MOVE',
      threadIds,
      destination,
    });

    threadIds.forEach((id) => {
      setBackgroundQueue({ type: 'add', threadId: `thread:${id}` });
    });

    if (threadId && threadIds.includes(threadId)) {
      setThreadId(null);
      setActiveReplyId(null);
    }
    const successMessage =
      destination === 'inbox'
        ? m['common.actions.movedToInbox']()
        : destination === 'spam'
          ? m['common.actions.movedToSpam']()
          : destination === 'bin'
            ? m['common.actions.movedToBin']()
            : m['common.actions.archived']();

    createPendingAction({
      type: 'MOVE',
      threadIds,
      params: { currentFolder, destination },
      optimisticId,
      execute: async () => {
        await moveThreadsTo({
          threadIds,
          currentFolder,
          destination,
        });

        if (mail.bulkSelected.length > 0) {
          setMail({ ...mail, bulkSelected: [] });
        }

        threadIds.forEach((id) => {
          setBackgroundQueue({ type: 'delete', threadId: `thread:${id}` });
        });
      },
      undo: () => {
        removeOptimisticAction(optimisticId);
        threadIds.forEach((id) => {
          setBackgroundQueue({ type: 'delete', threadId: `thread:${id}` });
        });
      },
      toastMessage: successMessage,
      folders: [currentFolder, destination],
    });
  }

  function optimisticDeleteThreads(threadIds: string[], currentFolder: string) {
    if (!threadIds.length) return;

    // setFocusedIndex(null);

    const optimisticId = addOptimisticAction({
      type: 'MOVE',
      threadIds,
      destination: 'bin',
    });

    threadIds.forEach((id) => {
      setBackgroundQueue({ type: 'add', threadId: `thread:${id}` });
    });

    if (threadId && threadIds.includes(threadId)) {
      setThreadId(null);
      setActiveReplyId(null);
    }
    createPendingAction({
      type: 'MOVE',
      threadIds,
      params: { currentFolder, destination: 'bin' },
      optimisticId,
      execute: async () => {
        await bulkDeleteThread({ ids: threadIds });

        if (mail.bulkSelected.length > 0) {
          setMail({ ...mail, bulkSelected: [] });
        }

        threadIds.forEach((id) => {
          setBackgroundQueue({ type: 'delete', threadId: `thread:${id}` });
        });
      },
      undo: () => {
        removeOptimisticAction(optimisticId);

        threadIds.forEach((id) => {
          setBackgroundQueue({ type: 'delete', threadId: `thread:${id}` });
        });
      },
      toastMessage: m['common.actions.movedToBin'](),
    });
  }

  const optimisticToggleImportant = useCallback(
    (threadIds: string[], isImportant: boolean) => {
      if (!threadIds.length) return;

      const optimisticId = addOptimisticAction({
        type: 'IMPORTANT',
        threadIds,
        important: isImportant,
      });

      createPendingAction({
        type: 'IMPORTANT',
        threadIds,
        params: { important: isImportant },
        optimisticId,
        execute: async () => {
          await toggleImportant({ ids: threadIds });
          applyTagTogglePatch(threadIds, 'IMPORTANT', isImportant);

          if (mail.bulkSelected.length > 0) {
            setMail((prev) => ({ ...prev, bulkSelected: [] }));
          }
        },
        undo: () => {
          removeOptimisticAction(optimisticId);
        },
        toastMessage: isImportant ? 'Marked as important' : 'Unmarked as important',
      });
    },
    [addOptimisticAction, applyTagTogglePatch, removeOptimisticAction, setMail, toggleImportant],
  );

  function optimisticToggleLabel(threadIds: string[], labelId: string, add: boolean) {
    if (!threadIds.length || !labelId) return;

    const optimisticId = addOptimisticAction({
      type: 'LABEL',
      threadIds,
      labelIds: [labelId],
      add,
    });

    createPendingAction({
      type: 'LABEL',
      threadIds,
      params: { labelId, add },
      optimisticId,
      execute: async () => {
        await modifyLabels({
          threadId: threadIds,
          addLabels: add ? [labelId] : [],
          removeLabels: add ? [] : [labelId],
        });
        applyLabelPatch(threadIds, labelId, add);

        if (mail.bulkSelected.length > 0) {
          setMail((prev) => ({ ...prev, bulkSelected: [] }));
        }
      },
      undo: () => {
        removeOptimisticAction(optimisticId);
      },
      toastMessage: add
        ? `Label added${threadIds.length > 1 ? ` to ${threadIds.length} threads` : ''}`
        : `Label removed${threadIds.length > 1 ? ` from ${threadIds.length} threads` : ''}`,
    });
  }

  function optimisticSnooze(threadIds: string[], currentFolder: string, wakeAt: Date) {
    if (!threadIds.length) return;

    const optimisticId = addOptimisticAction({
      type: 'SNOOZE',
      threadIds,
      wakeAt: wakeAt.toISOString(),
    });

    createPendingAction({
      type: 'SNOOZE',
      threadIds,
      params: { currentFolder, wakeAt: wakeAt.toISOString() },
      optimisticId,
      execute: async () => {
        await snoozeThreads({ ids: threadIds, wakeAt: wakeAt.toISOString() });

        if (mail.bulkSelected.length > 0) {
          setMail({ ...mail, bulkSelected: [] });
        }
      },
      undo: () => {
        removeOptimisticAction(optimisticId);
      },
      toastMessage: `Snoozed until ${wakeAt.toLocaleString()}`,
      folders: [currentFolder, 'snoozed'],
    });
  }

  function optimisticUnsnooze(threadIds: string[], currentFolder: string) {
    if (!threadIds.length) return;

    const optimisticId = addOptimisticAction({
      type: 'UNSNOOZE',
      threadIds,
    });

    createPendingAction({
      type: 'UNSNOOZE',
      threadIds,
      params: { currentFolder } as any,
      optimisticId,
      execute: async () => {
        await unsnoozeThreads({ ids: threadIds });
      },
      undo: () => {
        removeOptimisticAction(optimisticId);
      },
      toastMessage: 'Moved to Inbox',
      folders: [currentFolder, 'inbox'],
    });
  }

  function optimisticDeleteDraft(draftId: string) {
    if (!draftId) return;

    const optimisticId = addOptimisticAction({
      type: 'DELETE_DRAFT',
      threadIds: [draftId],
    });

    createPendingAction({
      type: 'DELETE_DRAFT',
      threadIds: [draftId],
      params: {} as any,
      optimisticId,
      execute: async () => {
        await deleteDraft({ id: draftId });
        await queryClient.invalidateQueries({ queryKey: trpc.drafts.list.queryKey() });
      },
      undo: () => {
        removeOptimisticAction(optimisticId);
      },
      toastMessage: 'Draft deleted',
    });
  }

  function undoLastAction() {
    if (!optimisticActionsManager.lastActionId) return;

    const lastAction = optimisticActionsManager.pendingActions.get(
      optimisticActionsManager.lastActionId,
    );
    if (!lastAction) return;

    lastAction.undo();

    optimisticActionsManager.pendingActions.delete(optimisticActionsManager.lastActionId);
    optimisticActionsManager.pendingActionsByType
      .get(lastAction.type)
      ?.delete(optimisticActionsManager.lastActionId);

    if (lastAction.toastId) {
      toast.dismiss(lastAction.toastId);
    }

    optimisticActionsManager.lastActionId = null;
  }

  return {
    optimisticMarkAsRead,
    optimisticMarkAsUnread,
    optimisticToggleStar,
    optimisticMoveThreadsTo,
    optimisticDeleteThreads,
    optimisticToggleImportant,
    optimisticToggleLabel,
    optimisticSnooze,
    optimisticUnsnooze,
    optimisticDeleteDraft,
    undoLastAction,
  };
}

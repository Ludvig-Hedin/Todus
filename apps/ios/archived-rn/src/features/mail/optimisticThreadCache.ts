import { QueryClient } from '@tanstack/react-query';

type ThreadListData = {
  threads: { id: string; historyId: string | null; $raw?: unknown }[];
  nextPageToken: string | null;
};

type ThreadTag = {
  id?: string;
  name?: string;
};

type ThreadMessage = {
  tags?: ThreadTag[];
};

type ThreadData = {
  latest?: ThreadMessage;
  messages?: ThreadMessage[];
};

export function getThreadListSnapshots(
  queryClient: QueryClient,
  listThreadsKey: readonly unknown[],
) {
  return queryClient.getQueriesData<ThreadListData>({
    queryKey: listThreadsKey,
  });
}

export function removeThreadIdsFromThreadListCaches(
  queryClient: QueryClient,
  listThreadsKey: readonly unknown[],
  threadIds: string[],
) {
  queryClient.setQueriesData(
    { queryKey: listThreadsKey },
    (previous: ThreadListData | undefined): ThreadListData | undefined => {
      if (!previous) return previous;
      return {
        ...previous,
        threads: previous.threads.filter((thread) => !threadIds.includes(thread.id)),
      };
    },
  );
}

export function restoreThreadListSnapshots(
  queryClient: QueryClient,
  snapshots: Array<[readonly unknown[], ThreadListData | undefined]>,
) {
  snapshots.forEach(([queryKey, data]) => {
    queryClient.setQueryData(queryKey, data);
  });
}

export function toggleStarInThreadCache(
  queryClient: QueryClient,
  threadKey: readonly unknown[],
): ThreadData | undefined {
  const previousThread = queryClient.getQueryData<ThreadData>(threadKey);

  queryClient.setQueryData(threadKey, (current: ThreadData | undefined): ThreadData | undefined => {
    if (!current) return current;

    const next: ThreadData = {
      ...current,
      latest: current.latest ? { ...current.latest } : undefined,
      messages: current.messages ? [...current.messages] : undefined,
    };

    const latestMessage =
      next.latest ??
      (next.messages && next.messages.length > 0
        ? { ...next.messages[next.messages.length - 1] }
        : undefined);

    if (!latestMessage) return current;

    const tags = latestMessage.tags ?? [];
    const hasStar = tags.some((tag) => tag.name === 'STARRED');
    const nextTags = hasStar
      ? tags.filter((tag) => tag.name !== 'STARRED')
      : [...tags, { name: 'STARRED' }];

    latestMessage.tags = nextTags;
    next.latest = latestMessage;

    if (next.messages && next.messages.length > 0) {
      const lastIndex = next.messages.length - 1;
      next.messages[lastIndex] = {
        ...next.messages[lastIndex],
        tags: nextTags,
      };
    }

    return next;
  });

  return previousThread;
}

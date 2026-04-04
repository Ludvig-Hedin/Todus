import { backgroundQueueAtom, isThreadInBackgroundQueueAtom } from '@/store/backgroundQueue';
import { useInfiniteQuery, useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import type { IGetThreadResponse } from '../../server/src/lib/driver/types';
import { useConnectionFilter } from '@/providers/connection-filter-provider';
import { useSearchValue } from '@/hooks/use-search-value';
import { useTRPC } from '@/providers/query-provider';
import useSearchLabels from './use-labels-search';
import { useSession } from '@/lib/auth-client';
import { useAtom, useAtomValue } from 'jotai';
import { useSettings } from './use-settings';
import { useParams } from 'react-router';
import { useTheme } from 'next-themes';
import { useQueryState } from 'nuqs';
import { useEffect, useMemo } from 'react';

const THREAD_SUMMARY_STALE_TIME_MS = 1000 * 60 * 5;
const THREAD_DETAIL_STALE_TIME_MS = 1000 * 60 * 15;
const THREAD_PREFETCH_COUNT = 3;

export const useThreads = () => {
  const { folder } = useParams<{ folder: string }>();
  const [searchValue] = useSearchValue();
  const [backgroundQueue] = useAtom(backgroundQueueAtom);
  const isInQueue = useAtomValue(isThreadInBackgroundQueueAtom);
  const trpc = useTRPC();
  const { labels } = useSearchLabels();
  const queryClient = useQueryClient();
  const [selectedThreadId] = useQueryState('threadId');
  const { enabledConnectionIds, isUnifiedView } = useConnectionFilter();

  // Convert Set to sorted array for stable query key
  const enabledIds = useMemo(
    () => [...enabledConnectionIds].sort(),
    [enabledConnectionIds],
  );

  // Single-connection mode: use existing listThreads endpoint (backward compatible)
  const singleConnectionQuery = useInfiniteQuery(
    trpc.mail.listThreads.infiniteQueryOptions(
      {
        q: searchValue.value,
        folder,
        labelIds: labels,
      },
      {
        initialCursor: '',
        getNextPageParam: (lastPage) => lastPage?.nextPageToken ?? null,
        staleTime: THREAD_SUMMARY_STALE_TIME_MS,
        refetchOnMount: false,
        refetchOnReconnect: true,
        enabled: !isUnifiedView,
      },
    ),
  );

  // Multi-connection mode: use listThreadsMulti endpoint
  const multiConnectionQuery = useInfiniteQuery({
    queryKey: [
      ['mail', 'listThreadsMulti'],
      { folder, q: searchValue.value, labelIds: labels, connectionIds: enabledIds },
    ],
    initialPageParam: {} as Record<string, string>,
    queryFn: async ({ pageParam }) =>
      queryClient.fetchQuery(
        trpc.mail.listThreadsMulti.queryOptions({
          folder,
          q: searchValue.value,
          labelIds: labels,
          connectionIds: enabledIds,
          cursors: pageParam as Record<string, string>,
        }),
      ),
    getNextPageParam: (lastPage) =>
      lastPage.nextCursors && Object.keys(lastPage.nextCursors).length > 0
        ? lastPage.nextCursors
        : undefined,
    staleTime: THREAD_SUMMARY_STALE_TIME_MS,
    refetchOnMount: false,
    refetchOnReconnect: true,
    enabled: isUnifiedView,
  });

  // Unified thread list regardless of mode
  const threads = useMemo(() => {
    if (isUnifiedView) {
      return multiConnectionQuery.data
        ? multiConnectionQuery.data.pages
            .flatMap((page) => page.threads)
            .filter(Boolean)
            .filter((e) => !isInQueue(`thread:${e.id}`))
        : [];
    }

    return singleConnectionQuery.data
      ? singleConnectionQuery.data.pages
          .flatMap((e) => e.threads)
          .filter(Boolean)
          .filter((e) => !isInQueue(`thread:${e.id}`))
      : [];
  }, [
    isUnifiedView,
    singleConnectionQuery.data,
    singleConnectionQuery.dataUpdatedAt,
    multiConnectionQuery.data,
    multiConnectionQuery.dataUpdatedAt,
    isInQueue,
    backgroundQueue,
  ]);

  // Combine query states for consistent API
  const activeQuery = isUnifiedView ? multiConnectionQuery : singleConnectionQuery;

  const isEmpty = useMemo(() => threads.length === 0, [threads]);
  const isReachingEnd = isUnifiedView
    ? isEmpty ||
      !multiConnectionQuery.data?.pages.length ||
      !multiConnectionQuery.data.pages[multiConnectionQuery.data.pages.length - 1]?.nextCursors ||
      Object.keys(
        multiConnectionQuery.data.pages[multiConnectionQuery.data.pages.length - 1]?.nextCursors ??
          {},
      ).length === 0
    : isEmpty ||
      (singleConnectionQuery.data &&
        !singleConnectionQuery.data.pages[singleConnectionQuery.data.pages.length - 1]?.nextPageToken);

  const loadMore = async () => {
    if (activeQuery.isLoading || activeQuery.isFetching) return;
    if (isUnifiedView) {
      await multiConnectionQuery.fetchNextPage();
      return;
    }
    await singleConnectionQuery.fetchNextPage();
  };

  useEffect(() => {
    if (!threads.length) return;

    const selectedIndex = selectedThreadId
      ? threads.findIndex((thread) => thread.id === selectedThreadId)
      : -1;
    const startIndex = selectedIndex >= 0 ? selectedIndex : 0;
    const threadIdsToPrefetch = threads
      .slice(startIndex, startIndex + THREAD_PREFETCH_COUNT)
      .map((thread) => thread.id);

    threadIdsToPrefetch.forEach((threadId) => {
      void queryClient.prefetchQuery(
        trpc.mail.get.queryOptions(
          { id: threadId },
          {
            staleTime: THREAD_DETAIL_STALE_TIME_MS,
          },
        ),
      );
    });
  }, [queryClient, selectedThreadId, threads, trpc]);

  return [activeQuery, threads, isReachingEnd, loadMore] as const;
};

export const useThread = (threadId: string | null) => {
  const { data: session } = useSession();
  const [_threadId] = useQueryState('threadId');
  const id = threadId ? threadId : _threadId;
  const trpc = useTRPC();
  const { data: settings } = useSettings();
  const { theme: systemTheme } = useTheme();

  const threadQuery = useQuery(
    trpc.mail.get.queryOptions(
      {
        id: id!,
      },
      {
        enabled: !!id && !!session?.user?.id,
        staleTime: THREAD_DETAIL_STALE_TIME_MS,
        refetchOnMount: false,
      },
    ),
  );

  const { latestDraft, isGroupThread, finalData, latestMessage } = useMemo(() => {
    if (!threadQuery.data) {
      return {
        latestDraft: undefined,
        isGroupThread: false,
        finalData: undefined,
        latestMessage: undefined,
      };
    }

    const latestDraft = threadQuery.data.latest?.id
      ? threadQuery.data.messages.findLast((e) => e.isDraft)
      : undefined;

    const isGroupThread = threadQuery.data.latest?.id
      ? (() => {
        const totalRecipients = [
          ...(threadQuery.data.latest.to || []),
          ...(threadQuery.data.latest.cc || []),
          ...(threadQuery.data.latest.bcc || []),
        ].length;
        return totalRecipients > 1;
      })()
      : false;

    const nonDraftMessages = threadQuery.data.messages.filter((e) => !e.isDraft);
    const latestMessage = nonDraftMessages[nonDraftMessages.length - 1];

    const finalData: IGetThreadResponse = {
      ...threadQuery.data,
      messages: nonDraftMessages,
    };

    return { latestDraft, isGroupThread, finalData, latestMessage };
  }, [threadQuery.data]);

  const { mutateAsync: processEmailContent } = useMutation(
    trpc.mail.processEmailContent.mutationOptions(),
  );

  // Extract image loading condition to avoid duplication
  const shouldLoadImages = useMemo(() => {
    if (!settings?.settings || !latestMessage?.sender?.email) return false;

    return settings.settings.externalImages ||
      settings.settings.trustedSenders?.includes(latestMessage.sender.email) ||
      false;
  }, [settings?.settings, latestMessage?.sender?.email]);

  // Prefetch query - intentionally unused, just for caching
  useQuery({
    queryKey: [
      'email-content',
      latestMessage?.id,
      shouldLoadImages,
      systemTheme,
    ],
    queryFn: async () => {
      if (!latestMessage?.decodedBody || !settings?.settings) return null;

      const userTheme =
        settings.settings.colorTheme === 'system' ? systemTheme : settings.settings.colorTheme;
      const theme = userTheme === 'dark' ? 'dark' : 'light';

      const result = await processEmailContent({
        html: latestMessage.decodedBody,
        shouldLoadImages,
        theme,
      });

      return {
        html: result.processedHtml,
        hasBlockedImages: result.hasBlockedImages,
      };
    },
    enabled: !!latestMessage?.decodedBody && !!settings?.settings,
    staleTime: 30 * 60 * 1000, // 30 minutes
    gcTime: 60 * 60 * 1000, // 1 hour
    refetchOnWindowFocus: false,
    refetchOnMount: false,
  });

  return { ...threadQuery, data: finalData, isGroupThread, latestDraft };
};

/**
 * Mail folder screen — displays the thread list for a given folder.
 * Equivalent to /mail/:folder on web (inbox, sent, draft, archive, etc.)
 */
import {
  getThreadListSnapshots,
  removeThreadIdsFromThreadListCaches,
  restoreThreadListSnapshots,
} from '../../../src/features/mail/optimisticThreadCache';
import {
  ActivityIndicator,
  Alert,
  Platform,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  useWindowDimensions,
  View,
} from 'react-native';
import { SwipeableThreadRow } from '../../../src/features/mail/SwipeableThreadRow';
import { ThreadDetailPane } from '../../../src/features/mail/ThreadDetailPane';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useLocalSearchParams, useRouter, useNavigation } from 'expo-router';
import { ThreadListItem } from '../../../src/features/mail/ThreadListItem';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useTRPC } from '../../../src/providers/QueryTrpcProvider';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '../../../src/shared/theme/ThemeContext';
import { sessionAtom } from '../../../src/shared/state/session';
import { haptics } from '../../../src/shared/utils/haptics';
import { Menu, Search, Plus } from 'lucide-react-native';
import { FlashList } from '@shopify/flash-list';
import { useAtomValue } from 'jotai';

export default function MailFolderScreen() {
  const { folder, threadId } = useLocalSearchParams<{ folder: string; threadId?: string }>();
  const router = useRouter();
  const navigation = useNavigation();
  const { width } = useWindowDimensions();
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const session = useAtomValue(sessionAtom);
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const activeFolder = folder ?? 'inbox';
  const isSplitLayout = Platform.OS === 'macos' || width >= 768;
  const listThreadsKey = trpc.mail.listThreads.queryKey();
  const archiveSnapshotsRef = useRef<ReturnType<typeof getThreadListSnapshots>>([]);
  const deleteSnapshotsRef = useRef<ReturnType<typeof getThreadListSnapshots>>([]);
  const [selectedThreadId, setSelectedThreadId] = useState<string | null>(
    threadId && typeof threadId === 'string' ? threadId : null,
  );

  const { data, isLoading, refetch, isRefetching } = useQuery({
    ...trpc.mail.listThreads.queryOptions({ folder: activeFolder }),
    enabled: !!session,
    staleTime: 30_000,
    gcTime: 5 * 60_000,
    refetchOnMount: false,
    refetchOnReconnect: false,
  });

  // Swipe action mutations
  const archiveMutation = useMutation({
    ...trpc.mail.bulkArchive.mutationOptions(),
    onMutate: ({ ids }) => {
      void queryClient.cancelQueries({ queryKey: listThreadsKey });
      const previousListSnapshots = getThreadListSnapshots(queryClient, listThreadsKey);
      archiveSnapshotsRef.current = previousListSnapshots;
      removeThreadIdsFromThreadListCaches(queryClient, listThreadsKey, ids);
      return undefined;
    },
    onError: (error) => {
      if (archiveSnapshotsRef.current.length > 0) {
        restoreThreadListSnapshots(queryClient, archiveSnapshotsRef.current);
      }
      Alert.alert(
        'Archive failed',
        error.message || 'Could not archive thread. Changes were reverted.',
      );
    },
    onSettled: () => queryClient.invalidateQueries({ queryKey: listThreadsKey }),
  });
  const deleteMutation = useMutation({
    ...trpc.mail.bulkDelete.mutationOptions(),
    onMutate: ({ ids }) => {
      void queryClient.cancelQueries({ queryKey: listThreadsKey });
      const previousListSnapshots = getThreadListSnapshots(queryClient, listThreadsKey);
      deleteSnapshotsRef.current = previousListSnapshots;
      removeThreadIdsFromThreadListCaches(queryClient, listThreadsKey, ids);
      return undefined;
    },
    onError: (error) => {
      if (deleteSnapshotsRef.current.length > 0) {
        restoreThreadListSnapshots(queryClient, deleteSnapshotsRef.current);
      }
      Alert.alert(
        'Delete failed',
        error.message || 'Could not delete thread. Changes were reverted.',
      );
    },
    onSettled: () => queryClient.invalidateQueries({ queryKey: listThreadsKey }),
  });

  const threads = useMemo(() => data?.threads ?? [], [data?.threads]);

  useEffect(() => {
    if (!isSplitLayout || !threadId || typeof threadId !== 'string') return;
    setSelectedThreadId(threadId);
  }, [isSplitLayout, threadId]);

  useEffect(() => {
    if (!isSplitLayout) return;
    if (threads.length === 0) {
      setSelectedThreadId(null);
      return;
    }

    const hasSelected =
      selectedThreadId && threads.some((thread: any) => thread.id === selectedThreadId);
    if (!hasSelected) {
      const fallbackId = threads[0]?.id;
      if (fallbackId) {
        setSelectedThreadId(fallbackId);
      }
    }
  }, [isSplitLayout, threads, selectedThreadId, activeFolder]);

  const folderLabel = useMemo(
    () => activeFolder.charAt(0).toUpperCase() + activeFolder.slice(1),
    [activeFolder],
  );

  const onRefresh = useCallback(() => {
    refetch();
  }, [refetch]);

  const openDrawer = () => {
    // Dispatch raw drawer action — avoids importing @react-navigation/native
    (navigation as any).openDrawer?.() ?? navigation.dispatch({ type: 'OPEN_DRAWER' });
  };

  const handleThreadPress = useCallback(
    (threadId: string) => {
      haptics.light();
      if (isSplitLayout) {
        setSelectedThreadId(threadId);
        router.setParams({ threadId });
        return;
      }
      router.push({
        pathname: '/(app)/(mail)/thread/[threadId]',
        params: { threadId },
      });
    },
    [isSplitLayout, router],
  );

  const handleArchive = useCallback(
    (threadId: string) => archiveMutation.mutate({ ids: [threadId] }),
    [archiveMutation],
  );

  const handleDelete = useCallback(
    (threadId: string) => deleteMutation.mutate({ ids: [threadId] }),
    [deleteMutation],
  );

  const closeSplitThread = useCallback(() => {
    setSelectedThreadId((current) => {
      const fallbackId = threads.find((thread: any) => thread.id !== current)?.id ?? null;
      if (fallbackId) {
        router.setParams({ threadId: fallbackId });
      }
      return fallbackId;
    });
  }, [threads, router]);

  const renderThreadList = () => {
    if (!session) {
      return (
        <View style={styles.loadingContainer}>
          <ActivityIndicator color={colors.primary} />
        </View>
      );
    }

    if (isLoading) {
      return (
        <View style={styles.loadingContainer}>
          <ActivityIndicator color={colors.primary} />
        </View>
      );
    }

    return (
      <FlashList
        data={threads}
        {...({ estimatedItemSize: 88, drawDistance: 320 } as any)}
        keyExtractor={(item: any) => item.id}
        renderItem={({ item }: { item: any }) => (
          <SwipeableThreadRow
            onArchive={() => handleArchive(item.id)}
            onDelete={() => handleDelete(item.id)}
          >
            <ThreadListItem
              threadId={item.id}
              onPress={handleThreadPress}
              selected={isSplitLayout && selectedThreadId === item.id}
            />
          </SwipeableThreadRow>
        )}
        refreshControl={
          <RefreshControl
            refreshing={isRefetching}
            onRefresh={onRefresh}
            tintColor={colors.mutedForeground}
          />
        }
        removeClippedSubviews
        ListEmptyComponent={
          <View style={styles.emptyState}>
            <Text style={[styles.emptyTitle, { color: colors.foreground }]}>
              Nothing to see here
            </Text>
            <Text style={[styles.emptySubtitle, { color: colors.mutedForeground }]}>
              This folder is empty.
            </Text>
          </View>
        }
      />
    );
  };

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      {/* Header with hamburger menu, title, search, and compose */}
      <View
        style={[
          styles.header,
          {
            paddingTop: insets.top + 8,
            backgroundColor: colors.background,
            borderBottomColor: colors.border,
          },
        ]}
      >
        <View style={styles.headerLeft}>
          {!isSplitLayout && (
            <Pressable
              style={({ pressed }) => [styles.iconButton, pressed && { opacity: 0.7 }]}
              onPress={openDrawer}
            >
              <Menu color={colors.foreground} size={24} />
            </Pressable>
          )}
          <Text style={[styles.headerTitle, { color: colors.foreground }]}>{folderLabel}</Text>
        </View>

        <View style={styles.headerRight}>
          <Pressable
            style={({ pressed }) => [styles.iconButton, pressed && { opacity: 0.7 }]}
            onPress={() => router.push('/search')}
          >
            <Search color={colors.foreground} size={22} />
          </Pressable>
          <Pressable
            style={[styles.composeButton, { backgroundColor: colors.primary }]}
            onPress={() => router.push('/compose')}
          >
            <Plus color={colors.primaryForeground} size={20} />
          </Pressable>
        </View>
      </View>

      {isSplitLayout ? (
        <View style={styles.splitContent}>
          <View style={[styles.listPane, { borderRightColor: colors.border }]}>
            {renderThreadList()}
          </View>
          <View style={styles.detailPane}>
            <ThreadDetailPane
              threadId={selectedThreadId}
              borderLeft
              onThreadClosed={closeSplitThread}
            />
          </View>
        </View>
      ) : (
        <View style={styles.listContainer}>{renderThreadList()}</View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingBottom: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  headerLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  headerRight: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  iconButton: {
    padding: 4,
  },
  headerTitle: {
    fontSize: 28,
    fontWeight: '800',
    letterSpacing: -0.5,
  },
  composeButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
  },
  listContainer: {
    flex: 1,
  },
  splitContent: {
    flex: 1,
    flexDirection: 'row',
  },
  listPane: {
    width: 420,
    borderRightWidth: StyleSheet.hairlineWidth,
  },
  detailPane: {
    flex: 1,
  },
  emptyState: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 64,
    paddingHorizontal: 24,
    gap: 8,
  },
  emptyTitle: {
    fontSize: 17,
    fontWeight: '600',
  },
  emptySubtitle: {
    fontSize: 14,
    textAlign: 'center',
  },
  loadingContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 48,
  },
});

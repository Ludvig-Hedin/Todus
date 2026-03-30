/**
 * Mail folder screen — displays the thread list for a given folder.
 * Equivalent to /mail/:folder on web (inbox, sent, draft, archive, etc.)
 */
import {
  ActivityIndicator,
  Alert,
  Platform,
  Pressable,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  useWindowDimensions,
  View,
} from 'react-native';
import {
  getThreadListSnapshots,
  removeThreadIdsFromThreadListCaches,
  restoreThreadListSnapshots,
} from '../../../src/features/mail/optimisticThreadCache';
import { Archive, CheckCheck, Inbox, Pencil, Search, Trash2, X } from 'lucide-react-native';
import { SwipeableThreadRow } from '../../../src/features/mail/SwipeableThreadRow';
import { ThreadDetailPane } from '../../../src/features/mail/ThreadDetailPane';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useLocalSearchParams, useRouter, useNavigation } from 'expo-router';
import { ThreadListItem } from '../../../src/features/mail/ThreadListItem';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useTRPC } from '../../../src/providers/QueryTrpcProvider';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '../../../src/shared/theme/ThemeContext';
import { spacing } from '@zero/design-tokens';
import { sessionAtom } from '../../../src/shared/state/session';
import { getNativeEnv } from '../../../src/shared/config/env';
import { haptics } from '../../../src/shared/utils/haptics';
import { FlashList } from '@shopify/flash-list';
import { useAtomValue } from 'jotai';
import { Image } from 'expo-image';

type MailCategory = {
  id: string;
  name: string;
  searchValue: string;
  order: number;
  isDefault?: boolean;
};

function getAvatarInitial(value?: string | null) {
  if (!value) return '?';
  const match = value.trim().match(/[A-Za-z0-9]/);
  return match ? match[0]!.toUpperCase() : '?';
}

export default function MailFolderScreen() {
  const { folder, threadId } = useLocalSearchParams<{ folder: string; threadId?: string }>();
  const router = useRouter();
  const navigation = useNavigation();
  const { width } = useWindowDimensions();
  const env = getNativeEnv();
  const { colors, ui } = useTheme();
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
  const [selectedThreadIds, setSelectedThreadIds] = useState<string[]>([]);
  const [selectedCategoryId, setSelectedCategoryId] = useState<string | null>(null);

  const settingsQuery = useQuery({
    ...trpc.settings.get.queryOptions(),
    enabled: !env.authBypassEnabled,
  });
  const defaultConnectionQuery = useQuery({
    ...trpc.connections.getDefault.queryOptions(),
    enabled: !!session && !env.authBypassEnabled,
    staleTime: 60_000,
    gcTime: 5 * 60_000,
  });
  const connectionsQuery = useQuery({
    ...trpc.connections.list.queryOptions(),
    enabled: !!session && !env.authBypassEnabled && !defaultConnectionQuery.data,
    staleTime: 60_000,
    gcTime: 5 * 60_000,
  });
  const categoryDefaultsQuery = useQuery(trpc.categories.defaults.queryOptions());
  const unreadCountQuery = useQuery({
    ...trpc.mail.listThreads.queryOptions({
      folder: 'inbox',
      q: 'UNREAD',
      maxResults: 100,
    }),
    enabled: !!session,
    staleTime: 30_000,
    gcTime: 5 * 60_000,
    refetchOnMount: false,
    refetchOnReconnect: false,
  });

  const categoryOptions = useMemo(() => {
    const settingsCategories = settingsQuery.data?.settings?.categories as
      | MailCategory[]
      | undefined;
    const fallbackCategories = categoryDefaultsQuery.data as MailCategory[] | undefined;
    const source = settingsCategories?.length ? settingsCategories : (fallbackCategories ?? []);
    return [...source].sort((a, b) => a.order - b.order);
  }, [categoryDefaultsQuery.data, settingsQuery.data?.settings?.categories]);

  const defaultCategoryId = useMemo(
    () =>
      categoryOptions.find((category) => category.isDefault)?.id ?? categoryOptions[0]?.id ?? null,
    [categoryOptions],
  );

  useEffect(() => {
    if (activeFolder !== 'inbox') {
      setSelectedCategoryId(null);
      return;
    }

    setSelectedCategoryId((current) => {
      if (current && categoryOptions.some((category) => category.id === current)) {
        return current;
      }
      return defaultCategoryId;
    });
  }, [activeFolder, categoryOptions, defaultCategoryId]);

  const selectedCategory = useMemo(
    () => categoryOptions.find((category) => category.id === selectedCategoryId) ?? null,
    [categoryOptions, selectedCategoryId],
  );

  const listThreadsInput = useMemo(() => {
    const query = activeFolder === 'inbox' ? (selectedCategory?.searchValue?.trim() ?? '') : '';
    return {
      folder: activeFolder,
      ...(query ? { q: query } : {}),
    };
  }, [activeFolder, selectedCategory?.searchValue]);

  const { data, isLoading, refetch, isRefetching } = useQuery({
    ...trpc.mail.listThreads.queryOptions(listThreadsInput),
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
  const isSelectionMode = selectedThreadIds.length > 0;
  const allVisibleThreadsSelected =
    threads.length > 0 && selectedThreadIds.length === threads.length;
  const activeConnection = useMemo(
    () => defaultConnectionQuery.data ?? connectionsQuery.data?.connections?.[0] ?? null,
    [connectionsQuery.data?.connections, defaultConnectionQuery.data],
  );
  const unreadCountLabel = useMemo(() => {
    if (unreadCountQuery.isLoading) return '...';
    const unreadCount = unreadCountQuery.data?.threads.length ?? 0;
    if (unreadCountQuery.data?.nextPageToken || unreadCount > 99) return '99+';
    return String(unreadCount);
  }, [unreadCountQuery.data?.nextPageToken, unreadCountQuery.data?.threads.length, unreadCountQuery.isLoading]);
  const headerSubtitle = useMemo(() => {
    if (isSelectionMode) {
      return `${selectedThreadIds.length} conversation${selectedThreadIds.length === 1 ? '' : 's'} selected`;
    }
    if (activeFolder === 'inbox' && selectedCategory) {
      return selectedCategory.name;
    }
    if (threads.length === 0) {
      return 'No conversations';
    }
    return `${threads.length} conversation${threads.length === 1 ? '' : 's'}`;
  }, [activeFolder, isSelectionMode, selectedCategory, selectedThreadIds.length, threads.length]);

  useEffect(() => {
    setSelectedThreadIds((current) =>
      current.filter((selectedId) => threads.some((thread: any) => thread.id === selectedId)),
    );
  }, [threads]);

  useEffect(() => {
    setSelectedThreadIds([]);
  }, [activeFolder]);

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
  const headerAvatarUri = activeConnection?.picture?.trim() ?? '';
  const headerIdentityLabel =
    activeConnection?.name?.trim() || activeConnection?.email?.trim() || 'Account';
  const headerAvatarInitial = getAvatarInitial(headerIdentityLabel);

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
      if (isSelectionMode) {
        setSelectedThreadIds((current) =>
          current.includes(threadId)
            ? current.filter((selectedId) => selectedId !== threadId)
            : [...current, threadId],
        );
        return;
      }
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
    [isSelectionMode, isSplitLayout, router],
  );

  const handleThreadLongPress = useCallback((threadId: string) => {
    haptics.medium();
    setSelectedThreadIds((current) => {
      if (current.includes(threadId)) return current;
      return [...current, threadId];
    });
  }, []);

  const clearSelection = useCallback(() => {
    setSelectedThreadIds([]);
  }, []);

  const selectAllVisibleThreads = useCallback(() => {
    setSelectedThreadIds(threads.map((thread: any) => thread.id));
  }, [threads]);

  const handleArchive = useCallback(
    (threadId: string) => archiveMutation.mutate({ ids: [threadId] }),
    [archiveMutation],
  );

  const handleDelete = useCallback(
    (threadId: string) => deleteMutation.mutate({ ids: [threadId] }),
    [deleteMutation],
  );

  const handleBulkArchive = useCallback(() => {
    if (selectedThreadIds.length === 0) return;
    archiveMutation.mutate({ ids: selectedThreadIds });
    setSelectedThreadIds([]);
  }, [archiveMutation, selectedThreadIds]);

  const handleBulkDelete = useCallback(() => {
    if (selectedThreadIds.length === 0) return;
    const selectedCount = selectedThreadIds.length;
    Alert.alert(
      'Delete selected threads?',
      `This will move ${selectedCount} thread${selectedCount === 1 ? '' : 's'} to trash.`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: () => {
            deleteMutation.mutate({ ids: selectedThreadIds });
            setSelectedThreadIds([]);
          },
        },
      ],
    );
  }, [deleteMutation, selectedThreadIds]);

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
        {...({ estimatedItemSize: 94, drawDistance: 320 } as any)}
        keyExtractor={(item: any) => item.id}
        contentContainerStyle={styles.listContent}
        renderItem={({ item }: { item: any }) => {
          const isRowSelected = isSelectionMode
            ? selectedThreadIds.includes(item.id)
            : isSplitLayout && selectedThreadId === item.id;

          return (
            <SwipeableThreadRow
              threadId={item.id}
              onArchive={() => handleArchive(item.id)}
              onDelete={() => handleDelete(item.id)}
              disabled={isSelectionMode}
            >
              <ThreadListItem
                threadId={item.id}
                onPress={handleThreadPress}
                onLongPress={handleThreadLongPress}
                selected={isRowSelected}
                selectionMode={isSelectionMode}
              />
            </SwipeableThreadRow>
          );
        }}
        refreshControl={
          <RefreshControl
            refreshing={isRefetching}
            onRefresh={onRefresh}
            tintColor={colors.mutedForeground}
          />
        }
        removeClippedSubviews
        ListEmptyComponent={
          <View
            style={[
              styles.emptyState,
              {
                backgroundColor: ui.surface,
                borderColor: ui.borderSubtle,
              },
            ]}
          >
            <Text style={[styles.emptyTitle, { color: colors.foreground }]}>
              {activeFolder === 'inbox' ? 'You are all caught up' : `No messages in ${folderLabel}`}
            </Text>
            <Text style={[styles.emptySubtitle, { color: colors.mutedForeground }]}>
              {activeFolder === 'inbox'
                ? 'Try another inbox category or pull to refresh.'
                : 'Pull to refresh or switch folders to keep triaging.'}
            </Text>
          </View>
        }
      />
    );
  };

  return (
    <View style={[styles.container, { backgroundColor: ui.canvas }]}>
      <View
        style={[
          styles.header,
          {
            paddingTop: insets.top + 8,
            backgroundColor: ui.canvas,
            borderBottomColor: ui.borderSubtle,
          },
        ]}
      >
        <View style={styles.headerLeft}>
          {isSelectionMode ? (
            <>
              <Pressable
                style={({ pressed }) => [
                  styles.iconButton,
                  styles.controlButton,
                  {
                    backgroundColor: pressed ? ui.pressed : ui.surface,
                    borderColor: ui.borderSubtle,
                  },
                ]}
                onPress={clearSelection}
                accessibilityRole="button"
                accessibilityLabel="Clear thread selection"
              >
                <X color={colors.foreground} size={18} />
              </Pressable>
              <View style={styles.headerTitleGroup}>
                <Text style={[styles.selectionTitle, { color: colors.foreground }]}>Selection</Text>
                <Text style={[styles.headerSubtitle, { color: colors.mutedForeground }]}>
                  {headerSubtitle}
                </Text>
              </View>
            </>
          ) : (
            <>
              <Pressable
                style={({ pressed }) => [
                  styles.headerBrandButton,
                  {
                    backgroundColor: pressed ? ui.pressed : ui.surface,
                    borderColor: ui.borderSubtle,
                  },
                ]}
                onPress={openDrawer}
                accessibilityRole="button"
                accessibilityLabel="Open mail menu"
              >
                <Inbox color={colors.foreground} size={18} />
              </Pressable>
              <View style={styles.headerTitleGroup}>
                <View style={styles.headerTitleRow}>
                  <Text style={[styles.headerTitle, { color: colors.foreground }]}>
                    {folderLabel}
                  </Text>
                  {activeFolder === 'inbox' && (
                    <Text style={[styles.headerCount, { color: colors.mutedForeground }]}>
                      {unreadCountLabel}
                    </Text>
                  )}
                </View>
                <Text style={[styles.headerSubtitle, { color: colors.mutedForeground }]}>
                  {activeFolder === 'inbox'
                    ? `${selectedCategory?.name ?? 'All Mail'}`
                    : headerSubtitle}
                </Text>
              </View>
            </>
          )}
        </View>

        <View style={styles.headerRight}>
          {isSelectionMode ? (
            <>
              {!allVisibleThreadsSelected && threads.length > 0 && (
                <Pressable
                  style={({ pressed }) => [
                    styles.iconButton,
                    styles.controlButton,
                    {
                      backgroundColor: pressed ? ui.pressed : ui.surface,
                      borderColor: ui.borderSubtle,
                    },
                  ]}
                  onPress={selectAllVisibleThreads}
                  accessibilityRole="button"
                  accessibilityLabel="Select all visible threads"
                >
                  <CheckCheck color={colors.foreground} size={18} />
                </Pressable>
              )}
              <Pressable
                style={({ pressed }) => [
                  styles.iconButton,
                  styles.controlButton,
                  {
                    backgroundColor: pressed ? ui.pressed : ui.surface,
                    borderColor: ui.borderSubtle,
                  },
                ]}
                onPress={handleBulkArchive}
                disabled={archiveMutation.isPending || deleteMutation.isPending}
                accessibilityRole="button"
                accessibilityLabel="Archive selected threads"
              >
                <Archive color={colors.foreground} size={18} />
              </Pressable>
              <Pressable
                style={({ pressed }) => [
                  styles.iconButton,
                  styles.controlButton,
                  {
                    backgroundColor: pressed ? ui.pressed : ui.surface,
                    borderColor: ui.borderSubtle,
                  },
                ]}
                onPress={handleBulkDelete}
                disabled={archiveMutation.isPending || deleteMutation.isPending}
                accessibilityRole="button"
                accessibilityLabel="Delete selected threads"
              >
                <Trash2 color={colors.destructive} size={18} />
              </Pressable>
            </>
          ) : (
            <Pressable
              style={({ pressed }) => [
                styles.headerAvatarButton,
                {
                  backgroundColor: pressed ? ui.pressed : ui.surfaceRaised,
                  borderColor: ui.borderStrong,
                },
              ]}
              onPress={() => router.push('/(app)/settings')}
              accessibilityRole="button"
              accessibilityLabel="Open account settings"
            >
              {headerAvatarUri ? (
                <Image source={{ uri: headerAvatarUri }} style={styles.headerAvatarImage} />
              ) : (
                <View style={[styles.headerAvatarFallback, { backgroundColor: ui.avatar }]}>
                  <Text style={[styles.headerAvatarText, { color: ui.avatarText }]}>
                    {headerAvatarInitial}
                  </Text>
                </View>
              )}
            </Pressable>
          )}
        </View>
      </View>

      {!isSelectionMode && (
        <View
          style={[
            styles.headerActions,
            { backgroundColor: ui.canvas, borderBottomColor: ui.borderSubtle },
          ]}
        >
          <Pressable
            style={({ pressed }) => [
              styles.commandPaletteButton,
              {
                backgroundColor: pressed ? ui.pressed : ui.surfaceRaised,
                borderColor: ui.borderSubtle,
              },
            ]}
            onPress={() => router.push('/search')}
            accessibilityRole="button"
            accessibilityLabel="Open search and command palette"
          >
            <Search color={colors.mutedForeground} size={16} />
            <Text style={[styles.commandPaletteLabel, { color: colors.mutedForeground }]}>
              Search emails
            </Text>
          </Pressable>
          <Pressable
            style={[
              styles.composeButton,
              {
                backgroundColor: ui.surfaceRaised,
                borderColor: ui.borderStrong,
                shadowColor: ui.shadow,
              },
            ]}
            onPress={() => router.push('/compose')}
            accessibilityRole="button"
            accessibilityLabel="Compose new email"
          >
            <Pencil color={ui.accent} size={17} />
          </Pressable>
        </View>
      )}

      {activeFolder === 'inbox' && categoryOptions.length > 0 && !isSelectionMode && (
        <View
          style={[
            styles.categoryTabsContainer,
            { borderBottomColor: ui.borderSubtle, backgroundColor: ui.canvas },
          ]}
        >
          <View
            style={[
              styles.categoryTabsTrack,
              { backgroundColor: ui.surface, borderColor: ui.borderSubtle },
            ]}
          >
            <ScrollView
              horizontal
              showsHorizontalScrollIndicator={false}
              contentContainerStyle={styles.categoryTabsContent}
            >
              {categoryOptions.map((category) => {
                const isActive = selectedCategoryId === category.id;
                return (
                  <Pressable
                    key={category.id}
                    style={[
                      styles.categoryTabChip,
                      {
                        backgroundColor: isActive ? ui.accentSoft : 'transparent',
                        borderColor: isActive ? ui.accentMuted : 'transparent',
                      },
                    ]}
                    onPress={() => setSelectedCategoryId(category.id)}
                    accessibilityRole="button"
                    accessibilityLabel={`Filter by ${category.name}`}
                    accessibilityState={{ selected: isActive }}
                  >
                    <Text
                      style={[
                        styles.categoryTabText,
                        {
                          color: isActive ? colors.foreground : colors.mutedForeground,
                        },
                      ]}
                    >
                      {category.name}
                    </Text>
                  </Pressable>
                );
              })}
            </ScrollView>
          </View>
        </View>
      )}

      {isSplitLayout ? (
        <View style={styles.splitContent}>
          <View style={[styles.listPane, { borderRightColor: ui.borderSubtle }]}>
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
    paddingHorizontal: spacing[4],
    paddingBottom: 14,
    borderBottomWidth: StyleSheet.hairlineWidth,
    gap: spacing[3],
  },
  headerLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    flex: 1,
  },
  headerRight: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing[2],
  },
  headerBrandButton: {
    width: 38,
    height: 38,
    borderRadius: 19,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
  },
  iconButton: {
    width: 36,
    height: 36,
    alignItems: 'center',
    justifyContent: 'center',
  },
  controlButton: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 16,
  },
  commandPaletteButton: {
    flex: 1,
    minHeight: 38,
    borderRadius: 19,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: spacing[3],
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  headerTitleGroup: {
    gap: 2,
    flex: 1,
  },
  headerTitleRow: {
    flexDirection: 'row',
    alignItems: 'baseline',
    gap: 8,
  },
  commandPaletteLabel: {
    fontSize: 13,
    lineHeight: 15,
    fontWeight: '500',
    letterSpacing: -0.12,
  },
  headerTitle: {
    fontSize: 24,
    lineHeight: 28,
    fontWeight: '700',
    letterSpacing: -0.56,
  },
  headerCount: {
    fontSize: 23,
    lineHeight: 27,
    fontWeight: '500',
    letterSpacing: -0.4,
  },
  headerSubtitle: {
    fontSize: 12,
    lineHeight: 15,
    letterSpacing: -0.08,
  },
  selectionTitle: {
    fontSize: 17,
    fontWeight: '700',
    letterSpacing: -0.3,
  },
  headerActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing[2],
    paddingHorizontal: spacing[4],
    paddingTop: 10,
    paddingBottom: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  headerAvatarButton: {
    width: 42,
    height: 42,
    borderRadius: 21,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
    overflow: 'hidden',
  },
  headerAvatarImage: {
    width: '100%',
    height: '100%',
  },
  headerAvatarFallback: {
    width: '100%',
    height: '100%',
    alignItems: 'center',
    justifyContent: 'center',
  },
  headerAvatarText: {
    fontSize: 14,
    lineHeight: 16,
    fontWeight: '700',
    letterSpacing: -0.16,
  },
  composeButton: {
    width: 38,
    height: 38,
    borderRadius: 19,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
    shadowOffset: { width: 0, height: 10 },
    shadowOpacity: 0.08,
    shadowRadius: 14,
    elevation: 3,
  },
  categoryTabsContainer: {
    paddingTop: 10,
    paddingBottom: 10,
    paddingHorizontal: spacing[4],
  },
  categoryTabsTrack: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 18,
  },
  categoryTabsContent: {
    paddingHorizontal: 4,
    paddingVertical: 4,
    gap: 4,
  },
  categoryTabChip: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 999,
    paddingHorizontal: 14,
    paddingVertical: 7,
  },
  categoryTabText: {
    fontSize: 11,
    lineHeight: 13,
    fontWeight: '600',
    letterSpacing: -0.06,
  },
  listContainer: {
    flex: 1,
  },
  listContent: {
    paddingTop: 0,
    paddingBottom: 24,
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
    alignItems: 'center',
    justifyContent: 'center',
    marginHorizontal: spacing[3],
    marginTop: 18,
    paddingVertical: 40,
    paddingHorizontal: spacing[5],
    gap: 6,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 24,
  },
  emptyTitle: {
    fontSize: 15,
    lineHeight: 19,
    fontWeight: '600',
    letterSpacing: -0.18,
  },
  emptySubtitle: {
    fontSize: 12,
    textAlign: 'center',
    lineHeight: 17,
    letterSpacing: -0.06,
  },
  loadingContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 48,
  },
});

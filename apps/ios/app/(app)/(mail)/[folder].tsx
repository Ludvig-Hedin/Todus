/**
 * Mail folder screen — displays the thread list for a given folder.
 * Equivalent to /mail/:folder on web (inbox, sent, draft, archive, etc.)
 */
import { useLocalSearchParams, useRouter, useNavigation } from 'expo-router';
import { useAtomValue } from 'jotai';
import { useCallback, useMemo } from 'react';
import {
  ActivityIndicator,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { FlashList } from '@shopify/flash-list';
import { Menu, Search, Plus } from 'lucide-react-native';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useTheme } from '../../../src/shared/theme/ThemeContext';
import { sessionAtom } from '../../../src/shared/state/session';
import { useTRPC } from '../../../src/providers/QueryTrpcProvider';
import { ThreadListItem } from '../../../src/features/mail/ThreadListItem';
import { SwipeableThreadRow } from '../../../src/features/mail/SwipeableThreadRow';
import { haptics } from '../../../src/shared/utils/haptics';

export default function MailFolderScreen() {
  const { folder } = useLocalSearchParams<{ folder: string }>();
  const router = useRouter();
  const navigation = useNavigation();
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const session = useAtomValue(sessionAtom);
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const activeFolder = folder ?? 'inbox';

  const { data, isLoading, refetch, isRefetching } = useQuery({
    ...trpc.mail.listThreads.queryOptions({ folder: activeFolder }),
    enabled: !!session,
  });

  // Swipe action mutations
  const archiveMutation = useMutation({
    ...trpc.mail.bulkArchive.mutationOptions(),
    onSettled: () => queryClient.invalidateQueries({ queryKey: trpc.mail.listThreads.queryKey() }),
  });
  const deleteMutation = useMutation({
    ...trpc.mail.bulkDelete.mutationOptions(),
    onSettled: () => queryClient.invalidateQueries({ queryKey: trpc.mail.listThreads.queryKey() }),
  });

  const threads = useMemo(() => data?.threads ?? [], [data?.threads]);

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
      router.push({
        pathname: '/(app)/(mail)/thread/[threadId]',
        params: { threadId },
      });
    },
    [router],
  );

  const handleArchive = useCallback(
    (threadId: string) => archiveMutation.mutate({ ids: [threadId] }),
    [archiveMutation],
  );

  const handleDelete = useCallback(
    (threadId: string) => deleteMutation.mutate({ ids: [threadId] }),
    [deleteMutation],
  );

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
          <Pressable
            style={({ pressed }) => [styles.iconButton, pressed && { opacity: 0.7 }]}
            onPress={openDrawer}
          >
            <Menu color={colors.foreground} size={24} />
          </Pressable>
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

      {/* Thread list */}
      <View style={styles.listContainer}>
        {session ? (
          isLoading ? (
            <View style={styles.loadingContainer}>
              <ActivityIndicator color={colors.primary} />
            </View>
          ) : (
            <FlashList
              data={threads}
              {...({ estimatedItemSize: 80 } as any)}
              keyExtractor={(item: any) => item.id}
              renderItem={({ item }: { item: any }) => (
                <SwipeableThreadRow
                  onArchive={() => handleArchive(item.id)}
                  onDelete={() => handleDelete(item.id)}
                >
                  <ThreadListItem threadId={item.id} onPress={handleThreadPress} />
                </SwipeableThreadRow>
              )}
              refreshControl={
                <RefreshControl
                  refreshing={isRefetching}
                  onRefresh={onRefresh}
                  tintColor={colors.mutedForeground}
                />
              }
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
          )
        ) : (
          <View style={styles.loadingContainer}>
            <ActivityIndicator color={colors.primary} />
          </View>
        )}
      </View>
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

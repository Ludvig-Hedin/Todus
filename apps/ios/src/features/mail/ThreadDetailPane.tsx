/**
 * ThreadDetailPane — reusable thread detail view for stacked and split layouts.
 */
import {
  getThreadListSnapshots,
  removeThreadIdsFromThreadListCaches,
  restoreThreadListSnapshots,
  toggleStarInThreadCache,
} from './optimisticThreadCache';
import {
  AlertTriangle,
  Archive,
  ArrowLeft,
  Forward,
  Reply,
  ReplyAll,
  Star,
  Trash2,
} from 'lucide-react-native';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { captureEvent } from '../../shared/telemetry/posthog';
import { useTRPC } from '../../providers/QueryTrpcProvider';
import { useTheme } from '../../shared/theme/ThemeContext';
import { haptics } from '../../shared/utils/haptics';
import { MessageCard } from './MessageCard';
import { useEffect, useRef } from 'react';
import { useRouter } from 'expo-router';

interface ThreadDetailPaneProps {
  threadId?: string | null;
  showBackButton?: boolean;
  onBackPress?: () => void;
  onThreadClosed?: () => void;
  borderLeft?: boolean;
}

export function ThreadDetailPane({
  threadId,
  showBackButton = false,
  onBackPress,
  onThreadClosed,
  borderLeft = false,
}: ThreadDetailPaneProps) {
  const router = useRouter();
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const listThreadsKey = trpc.mail.listThreads.queryKey();
  const archiveSnapshotsRef = useRef<ReturnType<typeof getThreadListSnapshots>>([]);
  const deleteSnapshotsRef = useRef<ReturnType<typeof getThreadListSnapshots>>([]);
  const spamSnapshotsRef = useRef<ReturnType<typeof getThreadListSnapshots>>([]);
  const starRollbackRef = useRef<{ threadKey: readonly unknown[]; previousThread: unknown } | null>(
    null,
  );
  const starEventNameRef = useRef<string | null>(null);

  const { data: threadData, isLoading } = useQuery({
    ...trpc.mail.get.queryOptions({ id: threadId ?? '' }),
    enabled: !!threadId,
    staleTime: 30_000,
    gcTime: 5 * 60_000,
    refetchOnMount: false,
    refetchOnReconnect: false,
  });

  const markAsReadMutation = useMutation(trpc.mail.markAsRead.mutationOptions());
  const markAsReadRef = useRef(markAsReadMutation.mutate);
  markAsReadRef.current = markAsReadMutation.mutate;

  useEffect(() => {
    if (threadId && threadData?.hasUnread) {
      markAsReadRef.current({ ids: [threadId] });
    }
  }, [threadId, threadData?.hasUnread]);

  const closeThread = () => {
    if (showBackButton) {
      onBackPress?.();
    }
    onThreadClosed?.();
  };

  const archiveMutation = useMutation({
    ...trpc.mail.bulkArchive.mutationOptions(),
    onMutate: ({ ids }) => {
      void queryClient.cancelQueries({ queryKey: listThreadsKey });
      const previousListSnapshots = getThreadListSnapshots(queryClient, listThreadsKey);
      archiveSnapshotsRef.current = previousListSnapshots;
      removeThreadIdsFromThreadListCaches(queryClient, listThreadsKey, ids);
      haptics.success();
      closeThread();
      return undefined;
    },
    onSuccess: () => {
      captureEvent('email_moved', {
        destination: 'archive',
        source: 'thread_detail',
      });
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
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: listThreadsKey });
    },
  });

  const deleteMutation = useMutation({
    ...trpc.mail.bulkDelete.mutationOptions(),
    onMutate: ({ ids }) => {
      void queryClient.cancelQueries({ queryKey: listThreadsKey });
      const previousListSnapshots = getThreadListSnapshots(queryClient, listThreadsKey);
      deleteSnapshotsRef.current = previousListSnapshots;
      removeThreadIdsFromThreadListCaches(queryClient, listThreadsKey, ids);
      haptics.warning();
      closeThread();
      return undefined;
    },
    onSuccess: () => {
      captureEvent('email_moved', {
        destination: 'bin',
        source: 'thread_detail',
      });
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
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: listThreadsKey });
    },
  });

  const spamMutation = useMutation({
    ...trpc.mail.modifyLabels.mutationOptions(),
    onMutate: ({ threadId: ids }) => {
      void queryClient.cancelQueries({ queryKey: listThreadsKey });
      const previousListSnapshots = getThreadListSnapshots(queryClient, listThreadsKey);
      spamSnapshotsRef.current = previousListSnapshots;
      removeThreadIdsFromThreadListCaches(queryClient, listThreadsKey, ids);
      haptics.warning();
      closeThread();
      return undefined;
    },
    onSuccess: () => {
      captureEvent('email_moved', {
        destination: 'spam',
        source: 'thread_detail',
      });
    },
    onError: (error) => {
      if (spamSnapshotsRef.current.length > 0) {
        restoreThreadListSnapshots(queryClient, spamSnapshotsRef.current);
      }
      Alert.alert(
        'Move failed',
        error.message || 'Could not move thread to spam. Changes were reverted.',
      );
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: listThreadsKey });
    },
  });

  const starMutation = useMutation({
    ...trpc.mail.toggleStar.mutationOptions(),
    onMutate: ({ ids }) => {
      const targetThreadId = ids[0];
      if (!targetThreadId) {
        return undefined;
      }

      const threadKey = trpc.mail.get.queryKey({ id: targetThreadId });
      void queryClient.cancelQueries({ queryKey: threadKey });
      const previousThread = toggleStarInThreadCache(queryClient, threadKey);
      starRollbackRef.current = { threadKey, previousThread };
      const wasStarred = Boolean(
        (previousThread as any)?.messages?.some((message: any) =>
          (message.tags ?? []).some((tag: any) => tag?.name?.toLowerCase() === 'starred'),
        ),
      );
      starEventNameRef.current = wasStarred ? 'email_unstarred' : 'email_starred';

      haptics.selection();
      return undefined;
    },
    onSuccess: () => {
      if (starEventNameRef.current) {
        captureEvent(starEventNameRef.current, { source: 'thread_detail' });
      }
    },
    onError: (error) => {
      if (starRollbackRef.current) {
        queryClient.setQueryData(
          starRollbackRef.current.threadKey,
          starRollbackRef.current.previousThread,
        );
      }
      starEventNameRef.current = null;
      Alert.alert(
        'Star failed',
        error.message || 'Could not update star state. Changes were reverted.',
      );
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: listThreadsKey });
      if (threadId) {
        queryClient.invalidateQueries({ queryKey: trpc.mail.get.queryKey({ id: threadId }) });
      }
      starEventNameRef.current = null;
    },
  });

  if (!threadId) {
    return (
      <View style={[styles.centered, { backgroundColor: colors.background }]}>
        <Text style={[styles.placeholderTitle, { color: colors.foreground }]}>Select a thread</Text>
        <Text style={[styles.placeholderSubtitle, { color: colors.mutedForeground }]}>
          Pick a conversation to view details.
        </Text>
      </View>
    );
  }

  const messages = threadData?.messages ?? [];
  const subject = messages[0]?.subject || '(no subject)';
  const labels = threadData?.labels ?? [];

  return (
    <View
      style={[
        styles.container,
        {
          backgroundColor: colors.background,
          borderLeftColor: colors.border,
        },
        borderLeft && styles.borderLeft,
      ]}
    >
      <View
        style={[
          styles.header,
          {
            paddingTop: showBackButton ? insets.top + 8 : 12,
            backgroundColor: colors.background,
            borderBottomColor: colors.border,
          },
        ]}
      >
        {showBackButton ? (
          <Pressable
            style={({ pressed }) => [styles.headerButton, pressed && { opacity: 0.6 }]}
            onPress={onBackPress}
          >
            <ArrowLeft size={22} color={colors.foreground} />
          </Pressable>
        ) : (
          <View style={styles.headerSpacer} />
        )}

        <View style={styles.headerActions}>
          <Pressable
            style={({ pressed }) => [styles.headerButton, pressed && { opacity: 0.6 }]}
            onPress={() => archiveMutation.mutate({ ids: [threadId] })}
          >
            <Archive size={20} color={colors.foreground} />
          </Pressable>
          <Pressable
            style={({ pressed }) => [styles.headerButton, pressed && { opacity: 0.6 }]}
            onPress={() => deleteMutation.mutate({ ids: [threadId] })}
          >
            <Trash2 size={20} color={colors.foreground} />
          </Pressable>
          <Pressable
            style={({ pressed }) => [styles.headerButton, pressed && { opacity: 0.6 }]}
            onPress={() =>
              spamMutation.mutate({
                threadId: [threadId],
                addLabels: ['SPAM'],
                removeLabels: ['INBOX'],
              })
            }
          >
            <AlertTriangle size={20} color={colors.foreground} />
          </Pressable>
          <Pressable
            style={({ pressed }) => [styles.headerButton, pressed && { opacity: 0.6 }]}
            onPress={() => starMutation.mutate({ ids: [threadId] })}
          >
            <Star size={20} color={colors.foreground} />
          </Pressable>
        </View>
      </View>

      {isLoading ? (
        <View style={styles.centered}>
          <ActivityIndicator color={colors.primary} />
        </View>
      ) : (
        <ScrollView contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + 80 }]}>
          <Text style={[styles.subject, { color: colors.foreground }]}>{subject}</Text>

          {labels.length > 0 && (
            <View style={styles.tags}>
              {labels.map((label: any) => (
                <View key={label.id} style={[styles.tag, { backgroundColor: colors.secondary }]}>
                  <Text style={[styles.tagText, { color: colors.secondaryForeground }]}>
                    {label.name}
                  </Text>
                </View>
              ))}
            </View>
          )}

          {messages.map((msg: any) => (
            <MessageCard key={msg.id} message={msg} />
          ))}
        </ScrollView>
      )}

      {!isLoading && messages.length > 0 && (
        <View style={[styles.replyActions, { bottom: insets.bottom + 20 }]}>
          <Pressable
            style={[styles.replyFab, styles.replyPrimary, { backgroundColor: colors.primary }]}
            onPress={() =>
              router.push({
                pathname: '/compose',
                params: { mode: 'reply', threadId },
              })
            }
          >
            <Reply size={20} color={colors.primaryForeground} />
            <Text style={[styles.replyFabText, { color: colors.primaryForeground }]}>Reply</Text>
          </Pressable>
          <Pressable
            style={[styles.replyFab, { backgroundColor: colors.secondary }]}
            onPress={() =>
              router.push({
                pathname: '/compose',
                params: { mode: 'replyAll', threadId },
              })
            }
          >
            <ReplyAll size={18} color={colors.secondaryForeground} />
            <Text style={[styles.replyFabText, { color: colors.secondaryForeground }]}>
              Reply All
            </Text>
          </Pressable>
          <Pressable
            style={[styles.replyFab, { backgroundColor: colors.secondary }]}
            onPress={() =>
              router.push({
                pathname: '/compose',
                params: { mode: 'forward', threadId },
              })
            }
          >
            <Forward size={18} color={colors.secondaryForeground} />
            <Text style={[styles.replyFabText, { color: colors.secondaryForeground }]}>
              Forward
            </Text>
          </Pressable>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  borderLeft: {
    borderLeftWidth: StyleSheet.hairlineWidth,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 12,
    paddingBottom: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  headerSpacer: {
    width: 30,
  },
  headerActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 16,
  },
  headerButton: {
    padding: 4,
  },
  content: {
    paddingHorizontal: 16,
    paddingTop: 16,
  },
  subject: {
    fontSize: 22,
    lineHeight: 28,
    fontWeight: '700',
    marginBottom: 12,
  },
  tags: {
    flexDirection: 'row',
    gap: 8,
    marginBottom: 24,
  },
  tag: {
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 4,
  },
  tagText: {
    fontSize: 12,
    fontWeight: '500',
  },
  replyActions: {
    position: 'absolute',
    left: 16,
    right: 16,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  replyFab: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderRadius: 28,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.2,
    shadowRadius: 4,
    elevation: 4,
  },
  replyPrimary: {
    flex: 1.25,
  },
  replyFabText: {
    fontSize: 14,
    fontWeight: '600',
  },
  centered: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
  },
  placeholderTitle: {
    fontSize: 18,
    fontWeight: '700',
    marginBottom: 8,
  },
  placeholderSubtitle: {
    fontSize: 14,
    textAlign: 'center',
  },
});

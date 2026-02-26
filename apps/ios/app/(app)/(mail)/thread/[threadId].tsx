/**
 * Thread detail screen — displays all messages in a conversation.
 * Equivalent to clicking a thread in the web app's mail list.
 * Fetches real data via mail.get TRPC query.
 */
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useRef } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Archive, Trash2, Star, AlertTriangle, ArrowLeft, Reply } from 'lucide-react-native';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useTheme } from '../../../../src/shared/theme/ThemeContext';
import { useTRPC } from '../../../../src/providers/QueryTrpcProvider';
import { MessageCard } from '../../../../src/features/mail/MessageCard';
import { haptics } from '../../../../src/shared/utils/haptics';

export default function ThreadDetailScreen() {
  const { threadId } = useLocalSearchParams<{ threadId: string }>();
  const router = useRouter();
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const trpc = useTRPC();
  const queryClient = useQueryClient();

  // Fetch thread data
  const { data: threadData, isLoading } = useQuery({
    ...trpc.mail.get.queryOptions({ id: threadId ?? '' }),
    enabled: !!threadId,
  });

  // Mark thread as read when loaded with unread status
  const markAsReadMutation = useMutation(trpc.mail.markAsRead.mutationOptions());
  const markAsReadRef = useRef(markAsReadMutation.mutate);
  markAsReadRef.current = markAsReadMutation.mutate;

  useEffect(() => {
    if (threadId && threadData?.hasUnread) {
      markAsReadRef.current({ ids: [threadId] });
    }
  }, [threadId, threadData?.hasUnread]);

  // Thread action mutations
  const archiveMutation = useMutation({
    ...trpc.mail.bulkArchive.mutationOptions(),
    onMutate: () => {
      haptics.success();
      router.back();
      return undefined;
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: trpc.mail.listThreads.queryKey() });
    },
  });

  const deleteMutation = useMutation({
    ...trpc.mail.bulkDelete.mutationOptions(),
    onMutate: () => {
      haptics.warning();
      router.back();
      return undefined;
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: trpc.mail.listThreads.queryKey() });
    },
  });

  const spamMutation = useMutation({
    ...trpc.mail.modifyLabels.mutationOptions(),
    onMutate: () => {
      haptics.warning();
      router.back();
      return undefined;
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: trpc.mail.listThreads.queryKey() });
    },
  });

  const starMutation = useMutation({
    ...trpc.mail.toggleStar.mutationOptions(),
    onMutate: () => { haptics.selection(); return undefined; },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: trpc.mail.listThreads.queryKey() });
    },
  });

  const messages = threadData?.messages ?? [];
  const subject = messages[0]?.subject || '(no subject)';
  const labels = threadData?.labels ?? [];

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      {/* Header with back + actions */}
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
        <Pressable
          style={({ pressed }) => [styles.headerButton, pressed && { opacity: 0.6 }]}
          onPress={() => router.back()}
        >
          <ArrowLeft size={22} color={colors.foreground} />
        </Pressable>

        <View style={styles.headerActions}>
          <Pressable
            style={({ pressed }) => [styles.headerButton, pressed && { opacity: 0.6 }]}
            onPress={() => threadId && archiveMutation.mutate({ ids: [threadId] })}
          >
            <Archive size={20} color={colors.foreground} />
          </Pressable>
          <Pressable
            style={({ pressed }) => [styles.headerButton, pressed && { opacity: 0.6 }]}
            onPress={() => threadId && deleteMutation.mutate({ ids: [threadId] })}
          >
            <Trash2 size={20} color={colors.foreground} />
          </Pressable>
          <Pressable
            style={({ pressed }) => [styles.headerButton, pressed && { opacity: 0.6 }]}
            onPress={() =>
              threadId &&
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
            onPress={() => threadId && starMutation.mutate({ ids: [threadId] })}
          >
            <Star size={20} color={colors.foreground} />
          </Pressable>
        </View>
      </View>

      {isLoading ? (
        <View style={styles.loadingContainer}>
          <ActivityIndicator color={colors.primary} />
        </View>
      ) : (
        <ScrollView
          contentContainerStyle={[
            styles.content,
            { paddingBottom: insets.bottom + 80 },
          ]}
        >
          {/* Subject */}
          <Text style={[styles.subject, { color: colors.foreground }]}>{subject}</Text>

          {/* Labels */}
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

          {/* Messages */}
          {messages.map((msg: any) => (
            <MessageCard key={msg.id} message={msg} />
          ))}
        </ScrollView>
      )}

      {/* Reply FAB */}
      {!isLoading && messages.length > 0 && (
        <Pressable
          style={[styles.replyFab, { backgroundColor: colors.primary }]}
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
    paddingHorizontal: 12,
    paddingBottom: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  headerActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 16,
  },
  headerButton: {
    padding: 4,
  },
  loadingContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
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
  replyFab: {
    position: 'absolute',
    bottom: 32,
    right: 16,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 20,
    paddingVertical: 14,
    borderRadius: 28,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.2,
    shadowRadius: 4,
    elevation: 4,
  },
  replyFabText: {
    fontSize: 15,
    fontWeight: '600',
  },
});

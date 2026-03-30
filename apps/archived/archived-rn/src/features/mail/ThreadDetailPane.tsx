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
  ActivityIndicator,
  ActionSheetIOS,
  Alert,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import {
  Archive,
  ArrowLeft,
  Forward,
  Mail,
  MailOpen,
  MoreHorizontal,
  Reply,
  ReplyAll,
  Star,
  Trash2,
} from 'lucide-react-native';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { captureEvent } from '../../shared/telemetry/posthog';
import { useEffect, useRef, useState } from 'react';
import { useTRPC } from '../../providers/QueryTrpcProvider';
import { useTheme } from '../../shared/theme/ThemeContext';
import { haptics } from '../../shared/utils/haptics';
import { sortThreadNotes } from './notesUtils';
import { MessageCard } from './MessageCard';
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
  const { colors, ui } = useTheme();
  const insets = useSafeAreaInsets();
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const listThreadsKey = trpc.mail.listThreads.queryKey();
  const threadKey = trpc.mail.get.queryKey({ id: threadId ?? '' });
  const notesQueryKey = trpc.notes.list.queryKey({ threadId: threadId ?? '' });
  const archiveSnapshotsRef = useRef<ReturnType<typeof getThreadListSnapshots>>([]);
  const deleteSnapshotsRef = useRef<ReturnType<typeof getThreadListSnapshots>>([]);
  const spamSnapshotsRef = useRef<ReturnType<typeof getThreadListSnapshots>>([]);
  const markAsReadRollbackRef = useRef<any>(null);
  const markAsUnreadRollbackRef = useRef<any>(null);
  const starRollbackRef = useRef<{ threadKey: readonly unknown[]; previousThread: unknown } | null>(
    null,
  );
  const starEventNameRef = useRef<string | null>(null);
  const suppressAutoReadRef = useRef(false);
  const [newNoteContent, setNewNoteContent] = useState('');
  const [editingNoteId, setEditingNoteId] = useState<string | null>(null);
  const [editingNoteContent, setEditingNoteContent] = useState('');
  const [notesExpanded, setNotesExpanded] = useState(false);

  const { data: threadData, isLoading } = useQuery({
    ...trpc.mail.get.queryOptions({ id: threadId ?? '' }),
    enabled: !!threadId,
    staleTime: 30_000,
    gcTime: 5 * 60_000,
    refetchOnMount: false,
    refetchOnReconnect: false,
  });

  const notesQuery = useQuery({
    ...trpc.notes.list.queryOptions({ threadId: threadId ?? '' }),
    enabled: !!threadId,
    staleTime: 30_000,
    refetchOnMount: false,
    refetchOnReconnect: false,
  });

  const markAsReadMutation = useMutation({
    ...trpc.mail.markAsRead.mutationOptions(),
    onMutate: async () => {
      await queryClient.cancelQueries({ queryKey: threadKey });
      markAsReadRollbackRef.current = queryClient.getQueryData(threadKey);
      queryClient.setQueryData(threadKey, (current: any) =>
        current ? { ...current, hasUnread: false } : current
      );
      return undefined;
    },
    onError: () => {
      if (markAsReadRollbackRef.current !== null) {
        queryClient.setQueryData(threadKey, markAsReadRollbackRef.current);
      }
    },
    onSettled: () => {
      markAsReadRollbackRef.current = null;
      queryClient.invalidateQueries({ queryKey: threadKey });
      queryClient.invalidateQueries({ queryKey: listThreadsKey });
    },
  });
  const markAsUnreadMutation = useMutation({
    ...trpc.mail.markAsUnread.mutationOptions(),
    onMutate: async () => {
      await queryClient.cancelQueries({ queryKey: threadKey });
      markAsUnreadRollbackRef.current = queryClient.getQueryData(threadKey);
      queryClient.setQueryData(threadKey, (current: any) =>
        current ? { ...current, hasUnread: true } : current
      );
      return undefined;
    },
    onError: () => {
      if (markAsUnreadRollbackRef.current !== null) {
        queryClient.setQueryData(threadKey, markAsUnreadRollbackRef.current);
      }
    },
    onSettled: () => {
      markAsUnreadRollbackRef.current = null;
      queryClient.invalidateQueries({ queryKey: threadKey });
      queryClient.invalidateQueries({ queryKey: listThreadsKey });
    },
  });
  const markAsReadRef = useRef(markAsReadMutation.mutate);
  markAsReadRef.current = markAsReadMutation.mutate;

  useEffect(() => {
    suppressAutoReadRef.current = false;
  }, [threadId]);

  useEffect(() => {
    if (threadId && threadData?.hasUnread && !suppressAutoReadRef.current) {
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

  const createNoteMutation = useMutation({
    ...trpc.notes.create.mutationOptions(),
    onSuccess: () => {
      haptics.success();
      setNewNoteContent('');
      queryClient.invalidateQueries({ queryKey: notesQueryKey });
    },
    onError: (error) => {
      Alert.alert('Add note failed', error.message || 'Could not add note.');
    },
  });

  const updateNoteMutation = useMutation({
    ...trpc.notes.update.mutationOptions(),
    onSuccess: () => {
      haptics.selection();
      setEditingNoteId(null);
      setEditingNoteContent('');
      queryClient.invalidateQueries({ queryKey: notesQueryKey });
    },
    onError: (error) => {
      Alert.alert('Update note failed', error.message || 'Could not update note.');
    },
  });

  const deleteNoteMutation = useMutation({
    ...trpc.notes.delete.mutationOptions(),
    onSuccess: () => {
      haptics.warning();
      queryClient.invalidateQueries({ queryKey: notesQueryKey });
    },
    onError: (error) => {
      Alert.alert('Delete note failed', error.message || 'Could not delete note.');
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
  const visibleLabels = formatVisibleThreadLabels(labels);
  const isStarred = messages.some((m: any) =>
    m.tags?.some((t: any) => t.name.toLowerCase() === 'starred')
  );
  const notes = ((notesQuery.data as { notes?: any[] } | undefined)?.notes ?? []) as any[];
  const sortedNotes = sortThreadNotes(notes);
  const notesSummary =
    notes.length === 0
      ? 'Keep quick reminders and follow-ups on the thread.'
      : `${notes.length} note${notes.length === 1 ? '' : 's'} saved on this thread.`;
  const markReadLabel = threadData?.hasUnread ? 'Mark as read' : 'Mark as unread';
  const ReadStateIcon = threadData?.hasUnread ? MailOpen : Mail;

  const createNote = () => {
    if (!threadId || !newNoteContent.trim()) return;
    createNoteMutation.mutate({
      threadId,
      content: newNoteContent.trim(),
      color: 'default',
      isPinned: false,
    });
  };

  const saveEditedNote = () => {
    if (!editingNoteId || !editingNoteContent.trim()) return;
    updateNoteMutation.mutate({
      noteId: editingNoteId,
      data: {
        content: editingNoteContent.trim(),
      },
    });
  };

  const toggleReadState = () => {
    if (!threadId) return;
    if (threadData?.hasUnread) {
      suppressAutoReadRef.current = false;
      markAsReadMutation.mutate({ ids: [threadId] });
      return;
    }
    suppressAutoReadRef.current = true;
    markAsUnreadMutation.mutate({ ids: [threadId] });
  };

  const openMoreActions = () => {
    const moveToSpam = () =>
      spamMutation.mutate({
        threadId: [threadId],
        addLabels: ['SPAM'],
        removeLabels: ['INBOX'],
      });

    if (Platform.OS === 'ios') {
      ActionSheetIOS.showActionSheetWithOptions(
        {
          options: [markReadLabel, 'Move to spam', 'Cancel'],
          cancelButtonIndex: 2,
          destructiveButtonIndex: 1,
        },
        (buttonIndex) => {
          if (buttonIndex === 0) {
            toggleReadState();
            return;
          }
          if (buttonIndex === 1) {
            moveToSpam();
          }
        },
      );
      return;
    }

    Alert.alert('Thread actions', 'Choose what to do with this conversation.', [
      { text: 'Cancel', style: 'cancel' as const },
      { text: markReadLabel, onPress: toggleReadState },
      { text: 'Move to spam', onPress: moveToSpam },
    ]);
  };

  return (
    <View
      style={[
        styles.container,
        {
          backgroundColor: ui.canvas,
          borderLeftColor: ui.borderSubtle,
        },
        borderLeft && styles.borderLeft,
      ]}
    >
      <View
        style={[
          styles.header,
          {
            paddingTop: showBackButton ? insets.top + 8 : 12,
            backgroundColor: ui.canvas,
          },
        ]}
      >
        {showBackButton ? (
          <Pressable
            style={({ pressed }) => [
              styles.headerButton,
              {
                backgroundColor: pressed ? ui.pressed : ui.surfaceRaised,
                borderColor: ui.borderSubtle,
              },
            ]}
            onPress={onBackPress}
            accessibilityRole="button"
            accessibilityLabel="Back to thread list"
          >
            <ArrowLeft size={20} color={colors.foreground} />
          </Pressable>
        ) : (
          <View style={styles.headerSpacer} />
        )}

        <View
          style={[
            styles.headerActions,
            {
              backgroundColor: ui.surfaceMuted,
              borderColor: ui.borderSubtle,
            },
          ]}
        >
          <Pressable
            style={({ pressed }) => [
              styles.headerButton,
              {
                backgroundColor: pressed ? ui.pressed : ui.surfaceRaised,
                borderColor: ui.borderSubtle,
              },
            ]}
            onPress={() => starMutation.mutate({ ids: [threadId] })}
            accessibilityRole="button"
            accessibilityLabel="Toggle star for thread"
          >
            <Star
              size={20}
              color={isStarred ? '#f59e0b' : colors.foreground}
              fill={isStarred ? '#f59e0b' : 'transparent'}
            />
          </Pressable>

          <Pressable
            style={({ pressed }) => [
              styles.headerButton,
              {
                backgroundColor: pressed ? ui.pressed : ui.surfaceRaised,
                borderColor: ui.borderSubtle,
              },
            ]}
            onPress={toggleReadState}
            accessibilityRole="button"
            accessibilityLabel={markReadLabel}
          >
            <ReadStateIcon size={20} color={colors.foreground} />
          </Pressable>

          <Pressable
            style={({ pressed }) => [
              styles.headerButton,
              {
                backgroundColor: pressed ? ui.pressed : ui.surfaceRaised,
                borderColor: ui.borderSubtle,
              },
            ]}
            onPress={() => {
              Alert.alert('Archive Thread', 'Are you sure you want to archive this thread?', [
                { text: 'Cancel', style: 'cancel' },
                {
                  text: 'Archive',
                  onPress: () => archiveMutation.mutate({ ids: [threadId] }),
                },
              ]);
            }}
            accessibilityRole="button"
            accessibilityLabel="Archive thread"
          >
            <Archive size={20} color={colors.foreground} />
          </Pressable>

          <Pressable
            style={({ pressed }) => [
              styles.headerButton,
              {
                backgroundColor: pressed ? ui.pressed : ui.surfaceRaised,
                borderColor: ui.borderSubtle,
              },
            ]}
            onPress={() => {
              Alert.alert('Delete Thread', 'Are you sure you want to move this thread to bin?', [
                { text: 'Cancel', style: 'cancel' },
                {
                  text: 'Delete',
                  style: 'destructive',
                  onPress: () => deleteMutation.mutate({ ids: [threadId] }),
                },
              ]);
            }}
            accessibilityRole="button"
            accessibilityLabel="Delete thread"
          >
            <Trash2 size={20} color={colors.foreground} />
          </Pressable>

          <Pressable
            style={({ pressed }) => [
              styles.headerButton,
              {
                backgroundColor: pressed ? ui.pressed : ui.surfaceRaised,
                borderColor: ui.borderSubtle,
              },
            ]}
            onPress={openMoreActions}
            accessibilityRole="button"
            accessibilityLabel="More actions"
          >
            <MoreHorizontal size={20} color={colors.foreground} />
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

          {visibleLabels.length > 0 && (
            <View style={styles.tags}>
              {visibleLabels.map((label) => (
                <View
                  key={label.id}
                    style={[
                      styles.tag,
                      {
                        backgroundColor: ui.surfaceMuted,
                        borderColor: ui.borderSubtle,
                      },
                    ]}
                >
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

          <View
            style={[
              styles.notesSection,
              {
                borderColor: ui.borderSubtle,
                backgroundColor: ui.surface,
              },
            ]}
          >
            <View style={styles.notesHeader}>
              <View style={styles.notesHeaderCopy}>
                <Text style={[styles.notesTitle, { color: colors.foreground }]}>Notes</Text>
                <Text style={[styles.notesSummary, { color: colors.mutedForeground }]}>
                  {notesSummary}
                </Text>
              </View>
              <View style={styles.notesHeaderActions}>
                <View style={[styles.notesCountBadge, { backgroundColor: ui.surfaceInset }]}>
                  <Text style={[styles.notesCount, { color: colors.mutedForeground }]}>
                    {notes.length}
                  </Text>
                </View>
                <Pressable onPress={() => setNotesExpanded((current) => !current)}>
                  <Text style={[styles.notesToggleText, { color: ui.accent }]}>
                    {notesExpanded ? 'Hide' : notes.length > 0 ? 'Show' : 'Add'}
                  </Text>
                </Pressable>
              </View>
            </View>

            {notesExpanded && (
              <>
                <View style={styles.noteComposer}>
                  <TextInput
                    style={[
                      styles.noteInput,
                      {
                        borderColor: ui.borderSubtle,
                        color: colors.foreground,
                        backgroundColor: ui.surfaceInset,
                      },
                    ]}
                    placeholder="Add a thread note"
                    placeholderTextColor={colors.mutedForeground}
                    value={newNoteContent}
                    onChangeText={setNewNoteContent}
                    multiline
                  />
                  <Pressable
                    style={[
                      styles.noteAddButton,
                      {
                        backgroundColor:
                          createNoteMutation.isPending || !newNoteContent.trim()
                            ? ui.surfaceInset
                            : ui.accent,
                      },
                    ]}
                    disabled={createNoteMutation.isPending || !newNoteContent.trim()}
                    onPress={createNote}
                  >
                    <Text
                      style={[
                        styles.noteAddText,
                        {
                          color:
                            createNoteMutation.isPending || !newNoteContent.trim()
                              ? colors.mutedForeground
                              : colors.primaryForeground,
                        },
                      ]}
                    >
                      {createNoteMutation.isPending ? 'Saving...' : 'Add'}
                    </Text>
                  </Pressable>
                </View>

                {sortedNotes.length === 0 ? (
                  <Text style={[styles.notesEmpty, { color: colors.mutedForeground }]}>
                    No notes yet. Use notes for reminders, follow-ups, or internal context.
                  </Text>
                ) : (
                  sortedNotes.map((note) => {
                    const isEditing = editingNoteId === note.id;
                    return (
                      <View
                        key={note.id}
                        style={[
                          styles.noteCard,
                          {
                            borderColor: ui.borderSubtle,
                            backgroundColor: ui.surfaceInset,
                          },
                        ]}
                      >
                        {isEditing ? (
                          <TextInput
                            style={[
                              styles.noteEditInput,
                              {
                                borderColor: ui.borderSubtle,
                                color: colors.foreground,
                                backgroundColor: ui.surfaceRaised,
                              },
                            ]}
                            value={editingNoteContent}
                            onChangeText={setEditingNoteContent}
                            multiline
                          />
                        ) : (
                          <Text style={[styles.noteContent, { color: colors.foreground }]}>
                            {note.content}
                          </Text>
                        )}
                        <View style={styles.noteMetaRow}>
                          <Text style={[styles.noteMetaText, { color: colors.mutedForeground }]}>
                            {new Date(note.updatedAt ?? note.createdAt).toLocaleString()}
                          </Text>
                          <View style={styles.noteActions}>
                            <Pressable
                              onPress={() => {
                                if (isEditing) {
                                  saveEditedNote();
                                } else {
                                  setEditingNoteId(note.id);
                                  setEditingNoteContent(note.content ?? '');
                                }
                              }}
                            >
                              <Text style={[styles.noteActionText, { color: ui.accent }]}>
                                {isEditing ? 'Save' : 'Edit'}
                              </Text>
                            </Pressable>
                            <Pressable
                              onPress={() =>
                                updateNoteMutation.mutate({
                                  noteId: note.id,
                                  data: { isPinned: !note.isPinned },
                                })
                              }
                            >
                              <Text style={[styles.noteActionText, { color: colors.foreground }]}>
                                {note.isPinned ? 'Unpin' : 'Pin'}
                              </Text>
                            </Pressable>
                            <Pressable
                              onPress={() =>
                                Alert.alert('Delete note?', 'This cannot be undone.', [
                                  { text: 'Cancel', style: 'cancel' },
                                  {
                                    text: 'Delete',
                                    style: 'destructive',
                                    onPress: () => deleteNoteMutation.mutate({ noteId: note.id }),
                                  },
                                ])
                              }
                            >
                              <Text
                                style={[styles.noteActionText, { color: colors.destructive }]}
                              >
                                Delete
                              </Text>
                            </Pressable>
                          </View>
                        </View>
                      </View>
                    );
                  })
                )}
              </>
            )}
          </View>
        </ScrollView>
      )}

      {!isLoading && messages.length > 0 && (
        <View
          style={[
            styles.replyActions,
            {
              bottom: Math.max(insets.bottom, 12),
              backgroundColor: ui.surface,
              borderColor: ui.borderStrong,
              shadowColor: ui.shadow,
            },
          ]}
        >
          <Pressable
            style={[styles.replyFab, styles.replyPrimary, { backgroundColor: ui.accent }]}
            onPress={() =>
              router.push({
                pathname: '/compose',
                params: { mode: 'reply', threadId },
              })
            }
            accessibilityRole="button"
            accessibilityLabel="Reply to thread"
          >
            <Reply size={14} color={colors.primaryForeground} />
            <Text style={[styles.replyFabText, { color: colors.primaryForeground }]}>Reply</Text>
          </Pressable>
          <Pressable
            style={[styles.replyFab, { backgroundColor: ui.surfaceInset }]}
            onPress={() =>
              router.push({
                pathname: '/compose',
                params: { mode: 'replyAll', threadId },
              })
            }
            accessibilityRole="button"
            accessibilityLabel="Reply all to thread"
          >
            <ReplyAll size={14} color={colors.foreground} />
            <Text style={[styles.replyFabText, { color: colors.foreground }]}>Reply All</Text>
          </Pressable>
          <Pressable
            style={[styles.replyFab, { backgroundColor: ui.surfaceInset }]}
            onPress={() =>
              router.push({
                pathname: '/compose',
                params: { mode: 'forward', threadId },
              })
            }
            accessibilityRole="button"
            accessibilityLabel="Forward thread"
          >
            <Forward size={14} color={colors.foreground} />
            <Text style={[styles.replyFabText, { color: colors.foreground }]}>Forward</Text>
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
    paddingHorizontal: 16,
    paddingBottom: 12,
  },
  headerSpacer: {
    width: 40,
  },
  headerActions: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'flex-end',
    gap: 6,
    paddingHorizontal: 6,
    paddingVertical: 6,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 22,
  },
  headerButton: {
    width: 34,
    height: 34,
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
  },
  content: {
    paddingHorizontal: 16,
    paddingTop: 16,
  },
  subject: {
    fontSize: 22,
    lineHeight: 27,
    fontWeight: '700',
    letterSpacing: -0.45,
    marginBottom: 12,
  },
  tags: {
    flexDirection: 'row',
    gap: 6,
    marginBottom: 16,
    flexWrap: 'wrap',
  },
  tag: {
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 999,
    borderWidth: StyleSheet.hairlineWidth,
  },
  tagText: {
    fontSize: 10,
    lineHeight: 12,
    fontWeight: '600',
    letterSpacing: -0.04,
  },
  notesSection: {
    marginTop: 6,
    marginBottom: 12,
    paddingHorizontal: 14,
    paddingVertical: 14,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 24,
    gap: 14,
  },
  notesHeader: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 10,
  },
  notesHeaderCopy: {
    flex: 1,
    gap: 3,
  },
  notesHeaderActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  notesTitle: {
    fontSize: 13,
    lineHeight: 16,
    fontWeight: '700',
    letterSpacing: -0.16,
  },
  notesSummary: {
    fontSize: 11,
    lineHeight: 15,
    letterSpacing: -0.06,
  },
  notesCountBadge: {
    minWidth: 24,
    borderRadius: 999,
    paddingHorizontal: 8,
    paddingVertical: 4,
    alignItems: 'center',
  },
  notesCount: {
    fontSize: 10,
    fontWeight: '600',
    letterSpacing: -0.04,
  },
  notesToggleText: {
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: -0.06,
  },
  noteComposer: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    gap: 8,
  },
  noteInput: {
    flex: 1,
    minHeight: 42,
    maxHeight: 110,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 16,
    paddingHorizontal: 12,
    paddingVertical: 9,
    fontSize: 12,
    lineHeight: 17,
    letterSpacing: -0.06,
  },
  noteAddButton: {
    borderRadius: 14,
    paddingHorizontal: 13,
    paddingVertical: 10,
  },
  noteAddText: {
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: -0.06,
  },
  notesEmpty: {
    fontSize: 11,
    lineHeight: 16,
    letterSpacing: -0.06,
  },
  noteCard: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 18,
    paddingHorizontal: 12,
    paddingVertical: 10,
    gap: 8,
  },
  noteContent: {
    fontSize: 12,
    lineHeight: 17,
    letterSpacing: -0.06,
  },
  noteEditInput: {
    minHeight: 58,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 14,
    paddingHorizontal: 10,
    paddingVertical: 8,
    fontSize: 12,
    lineHeight: 17,
    letterSpacing: -0.06,
  },
  noteMetaRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 10,
  },
  noteMetaText: {
    fontSize: 10,
    lineHeight: 13,
    letterSpacing: -0.04,
    flex: 1,
  },
  noteActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    flexWrap: 'wrap',
    justifyContent: 'flex-end',
  },
  noteActionText: {
    fontSize: 11,
    fontWeight: '600',
    letterSpacing: -0.06,
  },
  replyActions: {
    position: 'absolute',
    left: 16,
    right: 16,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 26,
    padding: 6,
    shadowOffset: { width: 0, height: 10 },
    shadowOpacity: 0.08,
    shadowRadius: 16,
    elevation: 4,
  },
  replyFab: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 4,
    paddingHorizontal: 8,
    paddingVertical: 8,
    borderRadius: 16,
  },
  replyPrimary: {
    flex: 1.25,
  },
  replyFabText: {
    fontSize: 11,
    fontWeight: '600',
    letterSpacing: -0.06,
  },
  centered: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
  },
  placeholderTitle: {
    fontSize: 17,
    fontWeight: '700',
    marginBottom: 6,
    letterSpacing: -0.24,
  },
  placeholderSubtitle: {
    fontSize: 12,
    textAlign: 'center',
    lineHeight: 17,
    letterSpacing: -0.06,
  },
});

const THREAD_LABEL_NAME_MAP: Record<string, string> = {
  CATEGORY_PERSONAL: 'Personal',
  CATEGORY_UPDATES: 'Updates',
  CATEGORY_PROMOTIONS: 'Promotions',
  CATEGORY_SOCIAL: 'Social',
  CATEGORY_FORUMS: 'Forums',
  IMPORTANT: 'Important',
  SPAM: 'Spam',
  TRASH: 'Trash',
  ARCHIVE: 'Archived',
};

const HIDDEN_THREAD_LABELS = new Set(['INBOX', 'UNREAD', 'STARRED', 'SENT', 'DRAFT']);

function formatVisibleThreadLabels(labels: Array<{ id: string; name: string }>) {
  return labels
    .filter((label) => !HIDDEN_THREAD_LABELS.has(label.name))
    .map((label) => ({
      ...label,
      name: THREAD_LABEL_NAME_MAP[label.name] ?? toTitleLabel(label.name),
    }));
}

function toTitleLabel(value: string) {
  return value
    .replace(/^CATEGORY_/, '')
    .toLowerCase()
    .split(/[_\s]+/)
    .filter(Boolean)
    .map((segment) => segment.charAt(0).toUpperCase() + segment.slice(1))
    .join(' ');
}

/**
 * ThreadListItem — individual thread row in the mail list.
 * Fetches thread data via TRPC and displays sender, subject, snippet, date, and read/star status.
 */
import { View, Text, StyleSheet, Pressable } from 'react-native';
import { useTRPC } from '../../providers/QueryTrpcProvider';
import { useTheme } from '../../shared/theme/ThemeContext';
import { useQuery } from '@tanstack/react-query';
import { Check, Star } from 'lucide-react-native';
import React, { useMemo } from 'react';

interface ThreadListItemProps {
  threadId: string;
  onPress: (threadId: string) => void;
  onLongPress?: (threadId: string) => void;
  selected?: boolean;
  selectionMode?: boolean;
}

function ThreadListItemComponent({
  threadId,
  onPress,
  onLongPress,
  selected = false,
  selectionMode = false,
}: ThreadListItemProps) {
  const { colors } = useTheme();
  const trpc = useTRPC();
  const { data: threadData, isLoading } = useQuery({
    ...trpc.mail.get.queryOptions({ id: threadId }),
    staleTime: 60_000,
    gcTime: 5 * 60_000,
    refetchOnMount: false,
    refetchOnReconnect: false,
  });

  const uiThread = useMemo(() => {
    if (!threadData || !threadData.messages || threadData.messages.length === 0) return null;
    const latest = threadData.latest || threadData.messages[threadData.messages.length - 1];
    if (!latest) return null;

    const isStarred =
      latest.tags?.some((tag: any) => tag?.name?.toLowerCase().startsWith('starred')) ?? false;

    return {
      id: threadId,
      sender: latest.sender?.name || latest.sender?.email || 'Unknown',
      subject: latest.subject || '(no subject)',
      snippet: latest.body?.replace(/<[^>]*>/g, '').slice(0, 120) || '',
      date: latest.receivedOn ? formatDate(new Date(latest.receivedOn)) : '',
      isRead: !threadData.hasUnread,
      isStarred,
    };
  }, [threadData, threadId]);

  if (isLoading) {
    return (
      <View style={[styles.container, { backgroundColor: colors.background }]}>
        <View style={styles.content}>
          {/* Row 1: sender + date skeleton */}
          <View style={styles.topRow}>
            <View style={[styles.skeleton, { backgroundColor: colors.secondary, width: '40%' }]} />
            <View style={[styles.skeleton, { backgroundColor: colors.secondary, width: 50 }]} />
          </View>
          {/* Row 2: subject skeleton */}
          <View
            style={[
              styles.skeleton,
              { backgroundColor: colors.secondary, width: '70%', marginBottom: 6 },
            ]}
          />
          {/* Row 3: snippet skeleton */}
          <View
            style={[
              styles.skeleton,
              { backgroundColor: colors.secondary, width: '90%', height: 12 },
            ]}
          />
        </View>
      </View>
    );
  }

  if (!uiThread) return null;

  const accessibilityLabel = `${uiThread.isRead ? 'Read' : 'Unread'} thread from ${uiThread.sender}. Subject: ${uiThread.subject}. ${uiThread.snippet}`.trim();

  return (
    <Pressable
      style={({ pressed }) => [
        styles.container,
        {
          backgroundColor: selected || pressed ? colors.secondary : colors.background,
          borderBottomColor: colors.border,
        },
      ]}
      onPress={() => onPress(uiThread.id)}
      onLongPress={onLongPress ? () => onLongPress(uiThread.id) : undefined}
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      accessibilityHint={
        selectionMode ? 'Double tap to toggle selection.' : 'Double tap to open thread details.'
      }
      accessibilityState={{ selected }}
    >
      {/* Unread indicator dot */}
      {!uiThread.isRead && <View style={[styles.unreadDot, { backgroundColor: colors.primary }]} />}
      {selectionMode && (
        <View
          style={[
            styles.selectionBadge,
            {
              borderColor: selected ? colors.primary : colors.border,
              backgroundColor: selected ? colors.primary : 'transparent',
            },
          ]}
        >
          {selected && <Check size={12} color={colors.primaryForeground} />}
        </View>
      )}

      <View style={styles.content}>
        {/* Top row: Sender + Date */}
        <View style={styles.topRow}>
          <Text
            style={[
              styles.sender,
              { color: uiThread.isRead ? colors.mutedForeground : colors.foreground },
              !uiThread.isRead && styles.unreadText,
            ]}
            numberOfLines={1}
          >
            {uiThread.sender}
          </Text>
          <Text
            style={[
              styles.date,
              { color: uiThread.isRead ? colors.mutedForeground : colors.primary },
              !uiThread.isRead && styles.unreadText,
            ]}
          >
            {uiThread.date}
          </Text>
        </View>

        {/* Subject + Star */}
        <View style={styles.middleRow}>
          <Text
            style={[
              styles.subject,
              { color: colors.foreground },
              !uiThread.isRead && styles.unreadText,
            ]}
            numberOfLines={1}
          >
            {uiThread.subject}
          </Text>
          {uiThread.isStarred && (
            <Star size={14} color="#f59e0b" fill="#f59e0b" style={styles.star} />
          )}
        </View>

        {/* Snippet preview */}
        <Text style={[styles.snippet, { color: colors.mutedForeground }]} numberOfLines={2}>
          {uiThread.snippet}
        </Text>
      </View>
    </Pressable>
  );
}

export const ThreadListItem = React.memo(
  ThreadListItemComponent,
  (previous, next) =>
    previous.threadId === next.threadId &&
    previous.selected === next.selected &&
    previous.selectionMode === next.selectionMode &&
    previous.onLongPress === next.onLongPress &&
    previous.onPress === next.onPress,
);

/** Formats a date as relative time or short date */
function formatDate(date: Date): string {
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffHours = diffMs / (1000 * 60 * 60);

  if (diffHours < 24 && date.getDate() === now.getDate()) {
    return date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  }

  if (diffHours < 48) {
    return 'Yesterday';
  }

  if (date.getFullYear() === now.getFullYear()) {
    return date.toLocaleDateString([], { month: 'short', day: 'numeric' });
  }

  return date.toLocaleDateString([], { month: 'short', day: 'numeric', year: '2-digit' });
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  unreadDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    position: 'absolute',
    left: 4,
    top: 18,
  },
  selectionBadge: {
    width: 18,
    height: 18,
    borderRadius: 9,
    borderWidth: 1.5,
    alignItems: 'center',
    justifyContent: 'center',
    position: 'absolute',
    left: 10,
    top: 12,
  },
  content: {
    flex: 1,
    paddingLeft: 4,
  },
  topRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'baseline',
    marginBottom: 2,
  },
  sender: {
    fontSize: 15,
    flex: 1,
    paddingRight: 8,
  },
  date: {
    fontSize: 13,
  },
  middleRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 4,
  },
  subject: {
    fontSize: 14,
    flex: 1,
    paddingRight: 8,
  },
  star: {
    marginLeft: 4,
  },
  snippet: {
    fontSize: 14,
    lineHeight: 18,
  },
  unreadText: {
    fontWeight: '700',
  },
  skeleton: {
    height: 16,
    borderRadius: 4,
    width: '60%',
    marginBottom: 8,
  },
  skeletonSmall: {
    height: 14,
    borderRadius: 4,
    width: '80%',
  },
});

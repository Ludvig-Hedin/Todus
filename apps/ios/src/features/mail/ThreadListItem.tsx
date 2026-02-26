/**
 * ThreadListItem — individual thread row in the mail list.
 * Fetches thread data via TRPC and displays sender, subject, snippet, date, and read/star status.
 */
import React, { useMemo } from 'react';
import { View, Text, StyleSheet, Pressable } from 'react-native';
import { useTheme } from '../../shared/theme/ThemeContext';
import { Star } from 'lucide-react-native';
import { useTRPC } from '../../providers/QueryTrpcProvider';
import { useQuery } from '@tanstack/react-query';

interface ThreadListItemProps {
  threadId: string;
  onPress: (threadId: string) => void;
}

export function ThreadListItem({ threadId, onPress }: ThreadListItemProps) {
  const { colors } = useTheme();
  const trpc = useTRPC();
  const { data: threadData, isLoading } = useQuery({
    ...trpc.mail.get.queryOptions({ id: threadId }),
  });

  const uiThread = useMemo(() => {
    if (!threadData || !threadData.messages || threadData.messages.length === 0) return null;
    const latest = threadData.latest || threadData.messages[threadData.messages.length - 1];
    if (!latest) return null;

    const isStarred = latest.tags?.some((t: any) => t.name === 'STARRED') ?? false;

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
          <View style={[styles.skeleton, { backgroundColor: colors.secondary, width: '70%', marginBottom: 6 }]} />
          {/* Row 3: snippet skeleton */}
          <View style={[styles.skeleton, { backgroundColor: colors.secondary, width: '90%', height: 12 }]} />
        </View>
      </View>
    );
  }

  if (!uiThread) return null;

  return (
    <Pressable
      style={({ pressed }) => [
        styles.container,
        {
          backgroundColor: pressed ? colors.secondary : colors.background,
          borderBottomColor: colors.border,
        },
      ]}
      onPress={() => onPress(uiThread.id)}
    >
      {/* Unread indicator dot */}
      {!uiThread.isRead && (
        <View style={[styles.unreadDot, { backgroundColor: colors.primary }]} />
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

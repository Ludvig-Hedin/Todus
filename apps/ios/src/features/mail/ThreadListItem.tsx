/**
 * ThreadListItem — individual thread row in the mail list.
 * Fetches thread data via TRPC and displays sender, subject, snippet, date, and read/star status.
 */
import { View, Text, StyleSheet, Pressable } from 'react-native';
import { useTRPC } from '../../providers/QueryTrpcProvider';
import { useTheme } from '../../shared/theme/ThemeContext';
import { typography, spacing } from '@zero/design-tokens';
import { Check, Star } from 'lucide-react-native';
import { SenderAvatar } from './SenderAvatar';
import { useQuery } from '@tanstack/react-query';
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
  const { colors, ui } = useTheme();
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
      senderEmail: latest.sender?.email ?? '',
      subject: latest.subject || '(no subject)',
      snippet: buildSnippetText(latest.processedHtml || latest.body || latest.decodedBody || ''),
      date: latest.receivedOn ? formatDate(new Date(latest.receivedOn)) : '',
      isRead: !threadData.hasUnread,
      isStarred,
      totalReplies: threadData.totalReplies,
    };
  }, [threadData, threadId]);

  if (isLoading) {
    return (
      <View
        style={[
          styles.container,
          {
            backgroundColor: ui.canvas,
          },
        ]}
      >
        <View style={[styles.avatarSkeleton, { backgroundColor: ui.surfaceInset }]} />
        <View style={[styles.content, styles.contentShell, { borderBottomColor: ui.borderSubtle }]}>
          <View style={styles.topRow}>
            <View style={[styles.skeleton, { backgroundColor: ui.surfaceInset, width: '42%' }]} />
            <View style={[styles.skeleton, { backgroundColor: ui.surfaceInset, width: 44 }]} />
          </View>
          <View
            style={[
              styles.skeleton,
              { backgroundColor: ui.surfaceInset, width: '68%', marginBottom: 5 },
            ]}
          />
          <View
            style={[
              styles.skeleton,
              { backgroundColor: ui.surfaceInset, width: '88%', height: 11 },
            ]}
          />
        </View>
      </View>
    );
  }

  if (!uiThread) return null;

  const accessibilityLabel =
    `${uiThread.isRead ? 'Read' : 'Unread'} thread from ${uiThread.sender}. Subject: ${uiThread.subject}. ${uiThread.snippet}`.trim();

  return (
    <Pressable
      style={({ pressed }) => [
        styles.container,
        {
          backgroundColor: selected ? ui.pressed : pressed ? ui.surfaceMuted : ui.canvas,
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
      <View style={styles.leadingSlot}>
        {selectionMode ? (
          <View
            style={[
              styles.selectionBadge,
              {
                borderColor: selected ? ui.accent : ui.borderStrong,
                backgroundColor: selected ? ui.accent : 'transparent',
              },
            ]}
          >
            {selected && <Check size={12} color={colors.primaryForeground} />}
          </View>
        ) : (
          <SenderAvatar email={uiThread.senderEmail} name={uiThread.sender} size={38} />
        )}
      </View>

      <View style={[styles.content, styles.contentShell, { borderBottomColor: ui.borderSubtle }]}>
        <View style={styles.topRow}>
          <View style={styles.senderRow}>
            <Text
              style={[
                styles.sender,
                { color: colors.foreground },
                !uiThread.isRead && styles.unreadText,
              ]}
              numberOfLines={1}
            >
              {uiThread.sender}
            </Text>
            {!uiThread.isRead && (
              <View style={[styles.inlineUnreadDot, { backgroundColor: ui.accent }]} />
            )}
            {uiThread.totalReplies > 1 && (
              <Text style={[styles.replyCount, { color: colors.mutedForeground }]}>
                [{uiThread.totalReplies}]
              </Text>
            )}
          </View>
          <Text
            style={[styles.date, { color: colors.mutedForeground }]}
          >
            {uiThread.date}
          </Text>
        </View>

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
            <Star size={14} color={ui.warning} fill={ui.warning} style={styles.star} />
          )}
        </View>

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

function buildSnippetText(value: string): string {
  return value
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, ' ')
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, ' ')
    .replace(/<head\b[^>]*>[\s\S]*?<\/head>/gi, ' ')
    .replace(/<svg\b[^>]*>[\s\S]*?<\/svg>/gi, ' ')
    .replace(/<!--[\s\S]*?-->/g, ' ')
    .replace(/@\w[\w-]*\s*\{[^}]*\}/g, ' ')
    .replace(/[.#:]?[\w-]+(?:\s+[.#:]?[\w-]+)*\s*\{[^}]*\}/g, ' ')
    .replace(/<[^>]*>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 120);
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    paddingHorizontal: spacing[4],
    paddingTop: 14,
    minHeight: 92,
  },
  leadingSlot: {
    width: 44,
    marginRight: 12,
    alignItems: 'center',
    paddingTop: 2,
  },
  avatarSkeleton: {
    width: 38,
    height: 38,
    borderRadius: 19,
  },
  selectionBadge: {
    width: 22,
    height: 22,
    borderRadius: 11,
    borderWidth: 1.5,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 5,
  },
  content: {
    flex: 1,
  },
  contentShell: {
    paddingBottom: 14,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  topRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: 3,
    gap: 10,
  },
  senderRow: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing[1] * 1.5,
    minWidth: 0,
    paddingRight: spacing[2],
  },
  sender: {
    fontSize: 14,
    lineHeight: 18,
    flexShrink: 1,
    letterSpacing: -0.22,
  },
  inlineUnreadDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    flexShrink: 0,
  },
  replyCount: {
    fontSize: typography.size.xs,
    fontWeight: '500',
    letterSpacing: -0.1,
  },
  date: {
    fontSize: 11,
    lineHeight: 14,
    fontWeight: '500',
    letterSpacing: -0.08,
    paddingTop: 1,
  },
  middleRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 6,
    gap: spacing[2],
  },
  subject: {
    fontSize: 15,
    lineHeight: 19,
    flex: 1,
    paddingRight: 6,
    letterSpacing: -0.24,
  },
  star: {
    marginLeft: 2,
  },
  snippet: {
    fontSize: 13,
    lineHeight: 18,
    letterSpacing: -0.12,
  },
  unreadText: {
    fontWeight: '600',
  },
  skeleton: {
    height: 10,
    borderRadius: 999,
    width: '60%',
    marginBottom: 7,
  },
});

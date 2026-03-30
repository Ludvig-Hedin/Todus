/**
 * SwipeableThreadRow — wraps a thread list item with swipe-revealed
 * triage actions for archive, read state, and delete.
 */
import { useTheme } from '../../shared/theme/ThemeContext';
import { Animated, Pressable, StyleSheet, Text, View } from 'react-native';
import { Swipeable } from 'react-native-gesture-handler';
import { Archive, Mail, MailOpen, Trash2 } from 'lucide-react-native';
import { haptics } from '../../shared/utils/haptics';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useTRPC } from '../../providers/QueryTrpcProvider';
import React, { useCallback, useRef } from 'react';

interface SwipeableThreadRowProps {
  threadId: string;
  children: React.ReactNode;
  onArchive: () => void;
  onDelete: () => void;
  disabled?: boolean;
}

export function SwipeableThreadRow({
  threadId,
  children,
  onArchive,
  onDelete,
  disabled = false,
}: SwipeableThreadRowProps) {
  const { colors, ui } = useTheme();
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const swipeableRef = useRef<Swipeable>(null);
  const markAsReadRollbackRef = useRef<any>(null);
  const markAsUnreadRollbackRef = useRef<any>(null);
  const threadKey = trpc.mail.get.queryKey({ id: threadId });

  const { data: threadData } = useQuery({
    ...trpc.mail.get.queryOptions({ id: threadId }),
    staleTime: 60_000,
    gcTime: 5 * 60_000,
    refetchOnMount: false,
    refetchOnReconnect: false,
  });

  const handleArchive = useCallback(() => {
    haptics.success();
    swipeableRef.current?.close();
    onArchive();
  }, [onArchive]);

  const handleDelete = useCallback(() => {
    haptics.warning();
    swipeableRef.current?.close();
    onDelete();
  }, [onDelete]);

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
    },
  });

  const handleToggleReadState = useCallback(() => {
    haptics.selection();
    swipeableRef.current?.close();
    if (threadData?.hasUnread) {
      markAsReadMutation.mutate({ ids: [threadId] });
      return;
    }
    markAsUnreadMutation.mutate({ ids: [threadId] });
  }, [markAsReadMutation, markAsUnreadMutation, threadData?.hasUnread, threadId]);

  const readActionLabel = threadData?.hasUnread ? 'Read' : 'Unread';
  const ReadActionIcon = threadData?.hasUnread ? MailOpen : Mail;

  const renderLeftActions = (
    progress: Animated.AnimatedInterpolation<number>,
    dragX: Animated.AnimatedInterpolation<number>,
  ) => {
    const opacity = progress.interpolate({
      inputRange: [0, 1],
      outputRange: [0.35, 1],
      extrapolate: 'clamp',
    });
    const translateX = dragX.interpolate({
      inputRange: [0, 140],
      outputRange: [-18, 0],
      extrapolate: 'clamp',
    });
    return (
      <Animated.View
        style={[
          styles.leftActions,
          {
            opacity,
            transform: [{ translateX }],
          },
        ]}
      >
        <Pressable
          style={[
            styles.actionButton,
            {
              backgroundColor: ui.surfaceInset,
              borderColor: ui.borderSubtle,
            },
          ]}
          onPress={handleToggleReadState}
          accessibilityRole="button"
          accessibilityLabel={`Mark thread as ${threadData?.hasUnread ? 'read' : 'unread'}`}
        >
          <ReadActionIcon size={18} color={colors.foreground} />
          <Text style={[styles.actionText, { color: colors.foreground }]}>{readActionLabel}</Text>
        </Pressable>
        <Pressable
          style={[
            styles.actionButton,
            {
              backgroundColor: ui.surfaceInset,
              borderColor: ui.borderSubtle,
            },
          ]}
          onPress={handleArchive}
          accessibilityRole="button"
          accessibilityLabel="Archive thread"
        >
          <Archive size={18} color={colors.foreground} />
          <Text style={[styles.actionText, { color: colors.foreground }]}>Archive</Text>
        </Pressable>
      </Animated.View>
    );
  };

  const renderRightActions = (
    progress: Animated.AnimatedInterpolation<number>,
    dragX: Animated.AnimatedInterpolation<number>,
  ) => {
    const opacity = progress.interpolate({
      inputRange: [0, 1],
      outputRange: [0.35, 1],
      extrapolate: 'clamp',
    });
    const translateX = dragX.interpolate({
      inputRange: [-80, 0],
      outputRange: [0, 18],
      extrapolate: 'clamp',
    });
    return (
      <Animated.View
        style={[
          styles.rightActions,
          {
            opacity,
            transform: [{ translateX }],
          },
        ]}
      >
        <Pressable
          style={[
            styles.actionButton,
            styles.destructiveActionButton,
            {
              backgroundColor: ui.surfaceInset,
              borderColor: ui.borderSubtle,
            },
          ]}
          onPress={handleDelete}
          accessibilityRole="button"
          accessibilityLabel="Delete thread"
        >
          <Trash2 size={18} color={colors.destructive} />
          <Text style={[styles.actionText, { color: colors.destructive }]}>Delete</Text>
        </Pressable>
      </Animated.View>
    );
  };

  if (disabled) {
    return <>{children}</>;
  }

  return (
    <Swipeable
      ref={swipeableRef}
      renderLeftActions={renderLeftActions}
      renderRightActions={renderRightActions}
      leftThreshold={84}
      rightThreshold={64}
      friction={2}
      overshootLeft={false}
      overshootRight={false}
    >
      {children}
    </Swipeable>
  );
}

const styles = StyleSheet.create({
  leftActions: {
    width: 176,
    paddingLeft: 12,
    paddingRight: 6,
    paddingBottom: 6,
    flexDirection: 'row',
    alignItems: 'stretch',
    gap: 6,
  },
  rightActions: {
    width: 92,
    paddingLeft: 6,
    paddingRight: 12,
    paddingBottom: 6,
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'flex-end',
  },
  actionButton: {
    flex: 1,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 20,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 5,
    paddingHorizontal: 10,
    paddingVertical: 8,
  },
  destructiveActionButton: {
    minWidth: 74,
  },
  actionText: {
    fontSize: 10,
    fontWeight: '700',
    letterSpacing: -0.08,
  },
});

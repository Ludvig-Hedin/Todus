import React, { useMemo } from 'react';
import { View, Text, StyleSheet, Pressable } from 'react-native';
import { useTheme } from '../../shared/theme/ThemeContext';
import { Star } from 'lucide-react-native';
import { useTRPC } from '../../app/providers/QueryTrpcProvider';
import { useQuery } from '@tanstack/react-query';

interface ThreadListItemProps {
    threadId: string;
    onPress: (threadId: string) => void;
}

export function ThreadListItem({ threadId, onPress }: ThreadListItemProps) {
    const { colors, typography: typo, spacing: sp } = useTheme();
    const trpc = useTRPC();
    const { data: threadData, isLoading } = useQuery({
        ...trpc.mail.get.queryOptions({ id: threadId }),
    });

    const uiThread = useMemo(() => {
        if (!threadData || !threadData.messages || threadData.messages.length === 0) return null;
        const latest = threadData.latest || threadData.messages[threadData.messages.length - 1];
        if (!latest) return null;

        const isStarred = latest.tags?.some(t => t.name === 'STARRED') ?? false;

        return {
            id: threadId,
            sender: latest.sender?.name || latest.sender?.email || 'Unknown',
            subject: latest.subject || '(no subject)',
            snippet: latest.body || '', // Raw email body without HTML tags ideally, but usually body works fallback
            date: latest.receivedOn ? new Date(latest.receivedOn).toLocaleDateString() : '',
            isRead: !threadData.hasUnread,
            isStarred,
        };
    }, [threadData, threadId]);

    if (isLoading) {
        return (
            <View style={[styles.container, { backgroundColor: colors.background, opacity: 0.5 }]}>
                <View style={styles.content}>
                    <Text style={{ color: colors.mutedForeground }}>Loading...</Text>
                </View>
            </View>
        );
    }

    if (!uiThread) return null;

    return (
        <Pressable
            style={({ pressed }) => [
                styles.container,
                { backgroundColor: pressed ? colors.secondary : colors.background },
            ]}
            onPress={() => onPress(uiThread.id)}
        >
            {/* Unread indicator */}
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

                {/* Second row: Subject + Star */}
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
                    {uiThread.isStarred && <Star size={14} color="#f59e0b" fill="#f59e0b" style={styles.star} />}
                </View>

                {/* Snippet */}
                <Text style={[styles.snippet, { color: colors.mutedForeground }]} numberOfLines={2}>
                    {uiThread.snippet}
                </Text>
            </View>
        </Pressable>
    );
}

const styles = StyleSheet.create({
    container: {
        flexDirection: 'row',
        paddingVertical: 12,
        paddingHorizontal: 16,
        borderBottomWidth: StyleSheet.hairlineWidth,
        borderBottomColor: '#333333', // fallback, will use theme colors nicely later or parent container
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
        paddingLeft: 4, // Space for unread dot
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
});

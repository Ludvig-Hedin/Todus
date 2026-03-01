/**
 * ThreadDetailScreen — displays a mail thread with messages.
 * Equivalent to the thread detail panel in `/mail/:folder` on web.
 *
 * Phase: N3 (stub for N1 navigation scaffold).
 */
import React, { useLayoutEffect } from 'react';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { ScrollView, StyleSheet, Text, View, Pressable, Alert } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Archive, Trash2, Star, AlertTriangle, Tag } from 'lucide-react-native';
import type { MailStackParamList } from '../../app/navigation/types';
import { useTheme } from '../../shared/theme/ThemeContext';
import { MessageCard, type DummyMessage } from './MessageCard';
import { useTRPC } from '../../app/providers/QueryTrpcProvider';
import { useMutation, useQueryClient } from '@tanstack/react-query';

type Props = NativeStackScreenProps<MailStackParamList, 'ThreadDetailScreen'>;

const DUMMY_MESSAGES: DummyMessage[] = [
    {
        id: 'msg_detail_1',
        sender: { name: 'Linear', email: 'notifications@linear.app' },
        date: 'Feb 15, 10:42 AM',
        bodyHtml: `
            <div style="padding: 20px; font-family: sans-serif;">
                <h2 style="margin-top: 0">New Issues Assigned</h2>
                <p>You have been assigned 3 new issues in the <strong>ZERO</strong> project:</p>
                <ul>
                    <li><a href="#" style="color: #6366f1; text-decoration: none;">ZERO-12</a>: Support for offline sync</li>
                    <li><a href="#" style="color: #6366f1; text-decoration: none;">ZERO-13</a>: Update billing UI for Pro tier</li>
                    <li><a href="#" style="color: #6366f1; text-decoration: none;">ZERO-14</a>: Fix push notifications payload</li>
                </ul>
                <p style="color: #666; font-size: 13px; margin-top: 30px;">
                    You are receiving this email because you are watching the ZERO project.
                </p>
            </div>
        `
    },
    {
        id: 'msg_detail_2',
        sender: { name: 'Ludvig Hedin', email: 'ludvig@example.com' },
        date: 'Feb 15, 11:30 AM',
        bodyHtml: `
            <div style="padding: 20px; font-family: sans-serif;">
                <p>Got it, I will take a look at the offline sync issue first. That seems to be the highest priority based on our last sync.</p>
                <br />
                <p>Thanks,</p>
                <p>Ludvig</p>
            </div>
        `
    }
];

export function ThreadDetailScreen({ route, navigation }: Props) {
    const { colors, typography: typo } = useTheme();
    const insets = useSafeAreaInsets();
    const { threadId } = route.params;

    const trpc = useTRPC();
    const queryClient = useQueryClient();

    const archiveMutation = useMutation({
        ...trpc.mail.bulkArchive.mutationOptions(),
        onMutate: () => {
            navigation.goBack();
            return undefined;
        },
        onSettled: () => {
            queryClient.invalidateQueries({ queryKey: trpc.mail.listThreads.queryKey() });
        },
    });

    const deleteMutation = useMutation({
        ...trpc.mail.bulkDelete.mutationOptions(),
        onMutate: () => {
            navigation.goBack();
            return undefined;
        },
        onSettled: () => {
            queryClient.invalidateQueries({ queryKey: trpc.mail.listThreads.queryKey() });
        },
    });

    const spamMutation = useMutation({
        ...trpc.mail.modifyLabels.mutationOptions(),
        onMutate: () => {
            navigation.goBack();
            return undefined;
        },
        onSettled: () => {
            queryClient.invalidateQueries({ queryKey: trpc.mail.listThreads.queryKey() });
        },
    });

    const starMutation = useMutation({
        ...trpc.mail.toggleStar.mutationOptions(),
        onSettled: () => {
            queryClient.invalidateQueries({ queryKey: trpc.mail.listThreads.queryKey() });
        },
    });

    useLayoutEffect(() => {
        navigation.setOptions({
            headerRight: () => (
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
                        onPress={() => spamMutation.mutate({ threadId: [threadId], addLabels: ['SPAM'], removeLabels: ['INBOX'] })}
                    >
                        <AlertTriangle size={20} color={colors.foreground} />
                    </Pressable>
                    <Pressable
                        style={({ pressed }) => [styles.headerButton, pressed && { opacity: 0.6 }]}
                        onPress={() => Alert.alert('Label', 'Label selection not yet implemented.')}
                    >
                        <Tag size={20} color={colors.foreground} />
                    </Pressable>
                    <Pressable
                        style={({ pressed }) => [styles.headerButton, pressed && { opacity: 0.6 }]}
                        onPress={() => starMutation.mutate({ ids: [threadId] })}
                    >
                        <Star size={20} color={colors.foreground} />
                    </Pressable>
                </View>
            ),
        });
    }, [navigation, colors, threadId, archiveMutation, deleteMutation, spamMutation, starMutation]);

    return (
        <View style={[styles.container, { backgroundColor: colors.background }]}>
            <ScrollView
                contentContainerStyle={[
                    styles.content,
                    { paddingBottom: insets.bottom + 16, paddingTop: 16 }
                ]}
            >
                <Text style={[styles.subject, { color: colors.foreground, fontFamily: typo.family.sans, fontWeight: '700' }]}>
                    Linear 3 new issues assigned to you
                </Text>

                <View style={[styles.tags, { marginBottom: 24 }]}>
                    <View style={[styles.tag, { backgroundColor: colors.secondary }]}>
                        <Text style={[styles.tagText, { color: colors.secondaryForeground }]}>Inbox</Text>
                    </View>
                </View>

                {DUMMY_MESSAGES.map((msg) => (
                    <MessageCard key={msg.id} message={msg} />
                ))}
            </ScrollView>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
    },
    content: {
        paddingHorizontal: 16,
    },
    headerActions: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 16,
    },
    headerButton: {
        padding: 4,
    },
    subject: {
        fontSize: 22,
        lineHeight: 28,
        marginBottom: 12,
    },
    tags: {
        flexDirection: 'row',
        gap: 8,
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
});

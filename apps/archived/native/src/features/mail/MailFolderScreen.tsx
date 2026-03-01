/**
 * MailFolderScreen — main mailbox view (thread list).
 * This is the primary screen of the app, equivalent to `/mail/:folder` on web.
 *
 * Phase: N3 (will be fully built out then; this is a working stub for N1 navigation scaffold).
 */
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { useAtomValue } from 'jotai';
import { useCallback, useMemo, useState } from 'react';
import {
    ActivityIndicator,
    Pressable,
    RefreshControl,
    StyleSheet,
    Text,
    View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { DrawerNavigationProp } from '@react-navigation/drawer';
import { FlashList } from '@shopify/flash-list';
import type { MailStackParamList, MailDrawerParamList } from '../../app/navigation/types';
import { useTheme } from '../../shared/theme/ThemeContext';
import { sessionAtom } from '../../shared/state/session';
import { Menu } from 'lucide-react-native';
import { ThreadListItem } from './ThreadListItem';

import { useTRPC } from '../../app/providers/QueryTrpcProvider';
import { useQuery } from '@tanstack/react-query';

type Props = NativeStackScreenProps<MailStackParamList, 'MailFolderScreen'>;

export function MailFolderScreen({ route, navigation }: Props) {
    const { colors, typography: typo, spacing: sp, isDark } = useTheme();
    const insets = useSafeAreaInsets();
    const session = useAtomValue(sessionAtom);
    const activeFolder = route.params?.folder ?? 'inbox';
    const trpc = useTRPC();

    const { data, isLoading, refetch, isRefetching } = useQuery({
        ...trpc.mail.listThreads.queryOptions({ folder: activeFolder }),
        enabled: !!session,
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
        // MailFolderScreen is inside MailStack which is inside MailDrawer
        const drawerNav = navigation.getParent() as any;
        drawerNav?.openDrawer();
    };

    const handleThreadPress = useCallback(
        (threadId: string) => {
            navigation.navigate('ThreadDetailScreen', { threadId, folder: activeFolder });
        },
        [navigation, activeFolder],
    );

    return (
        <View style={[styles.container, { backgroundColor: colors.background }]}>
            {/* Folder header */}
            <View
                style={[
                    styles.header,
                    {
                        paddingTop: insets.top + sp[2],
                        backgroundColor: colors.background,
                        borderBottomColor: colors.border,
                    },
                ]}
            >
                <View style={styles.headerLeft}>
                    <Pressable
                        style={({ pressed }) => [styles.menuButton, pressed && { opacity: 0.7 }]}
                        onPress={openDrawer}
                    >
                        <Menu color={colors.foreground} size={24} />
                    </Pressable>
                    <Text style={[styles.headerTitle, { color: colors.foreground }]}>{folderLabel}</Text>
                </View>

                <Pressable
                    style={[styles.composeButton, { backgroundColor: colors.primary }]}
                    onPress={() => {
                        // Navigate to compose modal — wired via RootNavigator in N4
                        const rootNav = navigation.getParent()?.getParent();
                        rootNav?.navigate('ComposeModal' as any);
                    }}
                >
                    <Text style={[styles.composeButtonText, { color: colors.primaryForeground }]}>+</Text>
                </Pressable>
            </View>

            {/* Thread list using FlashList */}
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
                                <View style={{ borderBottomColor: colors.border, borderBottomWidth: StyleSheet.hairlineWidth }}>
                                    <ThreadListItem threadId={item.id} onPress={handleThreadPress} />
                                </View>
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
    menuButton: {
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
    composeButtonText: {
        fontSize: 22,
        fontWeight: '300',
        lineHeight: 24,
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
    emptyDetail: {
        fontSize: 12,
        marginTop: 8,
    },
    loadingContainer: {
        flex: 1,
        alignItems: 'center',
        justifyContent: 'center',
        paddingVertical: 48,
    },
});

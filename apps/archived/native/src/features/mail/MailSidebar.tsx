import React from 'react';
import { View, Text, StyleSheet, Pressable, ScrollView } from 'react-native';
import { DrawerContentComponentProps } from '@react-navigation/drawer';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '../../shared/theme/ThemeContext';
import { useAtomValue } from 'jotai';
import { sessionAtom } from '../../shared/state/session';
import { Inbox, Send, Archive, Trash2, FileText, Star } from 'lucide-react-native';

type FolderDef = {
    id: string;
    label: string;
    icon: (color: string) => React.ReactNode;
};

const FOLDERS: FolderDef[] = [
    { id: 'inbox', label: 'Inbox', icon: (c) => <Inbox width={20} height={20} color={c} /> },
    { id: 'starred', label: 'Starred', icon: (c) => <Star width={20} height={20} color={c} /> },
    { id: 'sent', label: 'Sent', icon: (c) => <Send width={20} height={20} color={c} /> },
    { id: 'drafts', label: 'Drafts', icon: (c) => <FileText width={20} height={20} color={c} /> },
    { id: 'archive', label: 'Archive', icon: (c) => <Archive width={20} height={20} color={c} /> },
    { id: 'trash', label: 'Trash', icon: (c) => <Trash2 width={20} height={20} color={c} /> },
];

export function MailSidebar(props: DrawerContentComponentProps) {
    const { colors, typography: typo, spacing: sp } = useTheme();
    const insets = useSafeAreaInsets();
    const session = useAtomValue(sessionAtom);

    const navigateToFolder = (folderId: string) => {
        // Navigate inside the MailStack to MailFolderScreen with the selected folder
        props.navigation.navigate('MailStack', {
            screen: 'MailFolderScreen',
            params: { folder: folderId },
        });
    };

    // Get active folder from navigation state
    const mailStackState = props.state.routes.find((r) => r.name === 'MailStack')?.state;
    const activeRoute = mailStackState?.routes[mailStackState.index ?? 0];
    const activeFolder = (activeRoute?.params as any)?.folder ?? 'inbox';

    return (
        <View style={[styles.container, { backgroundColor: colors.background, paddingTop: insets.top }]}>
            <View style={styles.header}>
                <Text style={[styles.headerText, { color: colors.foreground }]}>Mail</Text>
            </View>

            <ScrollView style={styles.scrollContainer} contentContainerStyle={styles.scrollContent}>
                {FOLDERS.map((folder) => {
                    const isActive = activeFolder === folder.id;

                    return (
                        <Pressable
                            key={folder.id}
                            style={[
                                styles.folderRow,
                                { backgroundColor: isActive ? colors.secondary : 'transparent' }
                            ]}
                            onPress={() => navigateToFolder(folder.id)}
                        >
                            {folder.icon(isActive ? colors.foreground : colors.mutedForeground)}
                            <Text
                                style={[
                                    styles.folderLabel,
                                    {
                                        color: isActive ? colors.foreground : colors.mutedForeground,
                                        fontWeight: isActive ? '600' : '400'
                                    }
                                ]}
                            >
                                {folder.label}
                            </Text>

                            {/* Unread count logic to be added in next step */}
                            {folder.id === 'inbox' && (
                                <View style={[styles.badge, { backgroundColor: colors.primary }]}>
                                    <Text style={[styles.badgeText, { color: colors.primaryForeground }]}>3</Text>
                                </View>
                            )}
                        </Pressable>
                    );
                })}
            </ScrollView>

            {session && (
                <View style={[styles.footer, { borderTopColor: colors.border }]}>
                    <Text style={[styles.accountText, { color: colors.mutedForeground }]} numberOfLines={1}>
                        Signed In
                    </Text>
                </View>
            )}
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
    },
    header: {
        paddingHorizontal: 20,
        paddingVertical: 16,
        marginBottom: 8,
    },
    headerText: {
        fontSize: 24,
        fontWeight: '700',
    },
    scrollContainer: {
        flex: 1,
    },
    scrollContent: {
        paddingHorizontal: 12,
    },
    folderRow: {
        flexDirection: 'row',
        alignItems: 'center',
        paddingVertical: 12,
        paddingHorizontal: 16,
        borderRadius: 8,
        marginBottom: 4,
    },
    folderLabel: {
        fontSize: 16,
        marginLeft: 16,
        flex: 1,
    },
    badge: {
        paddingHorizontal: 6,
        paddingVertical: 2,
        borderRadius: 99,
    },
    badgeText: {
        fontSize: 12,
        fontWeight: '700',
    },
    footer: {
        padding: 16,
        borderTopWidth: StyleSheet.hairlineWidth,
    },
    accountText: {
        fontSize: 13,
    },
});

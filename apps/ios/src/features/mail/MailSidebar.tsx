/**
 * MailSidebar — drawer content showing mail folders, settings link, and logout.
 * Replaces the React Navigation drawer content with Expo Router navigation.
 */
import React from 'react';
import { View, Text, StyleSheet, Pressable, ScrollView } from 'react-native';
import { DrawerContentComponentProps } from '@react-navigation/drawer';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter, useGlobalSearchParams } from 'expo-router';
import { useTheme } from '../../shared/theme/ThemeContext';
import { useAtomValue, useSetAtom } from 'jotai';
import { sessionAtom, clearSessionAtom } from '../../shared/state/session';
import {
  Inbox,
  Send,
  Archive,
  Trash2,
  FileText,
  Star,
  Clock,
  AlertTriangle,
  Settings,
  LogOut,
} from 'lucide-react-native';

type FolderDef = {
  id: string;
  label: string;
  icon: (color: string) => React.ReactNode;
};

const FOLDERS: FolderDef[] = [
  { id: 'inbox', label: 'Inbox', icon: (c) => <Inbox width={20} height={20} color={c} /> },
  { id: 'starred', label: 'Starred', icon: (c) => <Star width={20} height={20} color={c} /> },
  { id: 'sent', label: 'Sent', icon: (c) => <Send width={20} height={20} color={c} /> },
  { id: 'draft', label: 'Drafts', icon: (c) => <FileText width={20} height={20} color={c} /> },
  { id: 'snoozed', label: 'Snoozed', icon: (c) => <Clock width={20} height={20} color={c} /> },
  { id: 'archive', label: 'Archive', icon: (c) => <Archive width={20} height={20} color={c} /> },
  { id: 'spam', label: 'Spam', icon: (c) => <AlertTriangle width={20} height={20} color={c} /> },
  { id: 'bin', label: 'Trash', icon: (c) => <Trash2 width={20} height={20} color={c} /> },
];

export function MailSidebar(props: DrawerContentComponentProps) {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const session = useAtomValue(sessionAtom);
  const clearSession = useSetAtom(clearSessionAtom);
  const globalParams = useGlobalSearchParams();
  const activeFolder = (globalParams.folder as string) ?? 'inbox';

  const navigateToFolder = (folderId: string) => {
    router.push(`/(app)/(mail)/${folderId}` as any);
    props.navigation.closeDrawer();
  };

  const handleLogout = async () => {
    await clearSession();
  };

  return (
    <View style={[styles.container, { backgroundColor: colors.background, paddingTop: insets.top }]}>
      {/* Header */}
      <View style={styles.header}>
        <Text style={[styles.headerText, { color: colors.foreground }]}>Mail</Text>
      </View>

      {/* Folder list */}
      <ScrollView style={styles.scrollContainer} contentContainerStyle={styles.scrollContent}>
        {FOLDERS.map((folder) => {
          const isActive = activeFolder === folder.id;
          return (
            <Pressable
              key={folder.id}
              style={[
                styles.folderRow,
                { backgroundColor: isActive ? colors.secondary : 'transparent' },
              ]}
              onPress={() => navigateToFolder(folder.id)}
            >
              {folder.icon(isActive ? colors.foreground : colors.mutedForeground)}
              <Text
                style={[
                  styles.folderLabel,
                  {
                    color: isActive ? colors.foreground : colors.mutedForeground,
                    fontWeight: isActive ? '600' : '400',
                  },
                ]}
              >
                {folder.label}
              </Text>
            </Pressable>
          );
        })}

        {/* Divider */}
        <View style={[styles.divider, { backgroundColor: colors.border }]} />

        {/* Settings */}
        <Pressable
          style={styles.folderRow}
          onPress={() => {
            router.push('/(app)/settings' as any);
            props.navigation.closeDrawer();
          }}
        >
          <Settings width={20} height={20} color={colors.mutedForeground} />
          <Text style={[styles.folderLabel, { color: colors.mutedForeground }]}>Settings</Text>
        </Pressable>
      </ScrollView>

      {/* Footer with logout */}
      {session && (
        <View style={[styles.footer, { borderTopColor: colors.border }]}>
          <Pressable
            style={styles.logoutRow}
            onPress={handleLogout}
          >
            <LogOut width={18} height={18} color={colors.destructive} />
            <Text style={[styles.logoutText, { color: colors.destructive }]}>Sign Out</Text>
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
  divider: {
    height: StyleSheet.hairlineWidth,
    marginVertical: 12,
    marginHorizontal: 16,
  },
  footer: {
    padding: 16,
    borderTopWidth: StyleSheet.hairlineWidth,
  },
  logoutRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingVertical: 8,
    paddingHorizontal: 4,
  },
  logoutText: {
    fontSize: 15,
    fontWeight: '500',
  },
});

/**
 * MailSidebar — drawer content showing mail folders, settings link, and logout.
 * Replaces the React Navigation drawer content with Expo Router navigation.
 */
import {
  Inbox,
  Send,
  Archive,
  Trash2,
  FileText,
  Star,
  Clock,
  AlertTriangle,
  Search,
  Settings,
  Sparkles,
  LogOut,
} from 'lucide-react-native';
import { View, Text, StyleSheet, Pressable, ScrollView } from 'react-native';
import { useRouter, useGlobalSearchParams, usePathname } from 'expo-router';
import { sessionAtom, clearSessionAtom } from '../../shared/state/session';
import { DrawerContentComponentProps } from '@react-navigation/drawer';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '../../shared/theme/ThemeContext';
import { useAtomValue, useSetAtom } from 'jotai';
import React from 'react';

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
  const { colors, ui } = useTheme();
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const pathname = usePathname();
  const session = useAtomValue(sessionAtom);
  const clearSession = useSetAtom(clearSessionAtom);
  const globalParams = useGlobalSearchParams();
  const activeFolder = (globalParams.folder as string) ?? 'inbox';
  const assistantActive = pathname.includes('/assistant');
  const settingsActive = pathname.includes('/settings');
  const searchActive = pathname === '/search';

  const navigateToFolder = (folderId: string) => {
    router.push(`/(app)/(mail)/${folderId}` as any);
    props.navigation.closeDrawer();
  };

  const navigateToRoute = (pathname: '/search' | '/(app)/assistant' | '/(app)/settings') => {
    router.push(pathname as any);
    props.navigation.closeDrawer();
  };

  const handleLogout = async () => {
    await clearSession();
  };

  return (
    <View style={[styles.container, { backgroundColor: ui.canvas, paddingTop: insets.top }]}>
      <View
        style={[
          styles.header,
          {
            backgroundColor: ui.surfaceRaised,
            borderColor: ui.borderSubtle,
          },
        ]}
      >
        <Text style={[styles.headerEyebrow, { color: colors.mutedForeground }]}>Todus</Text>
        <Text style={[styles.headerText, { color: colors.foreground }]}>Mail</Text>
        <Text style={[styles.headerSubtext, { color: colors.mutedForeground }]}>
          Clean triage, threaded focus, quick actions.
        </Text>
      </View>

      <ScrollView style={styles.scrollContainer} contentContainerStyle={styles.scrollContent}>
        {FOLDERS.map((folder) => {
          const isActive = activeFolder === folder.id;
          return (
            <Pressable
              key={folder.id}
              style={[
                styles.folderRow,
                {
                  backgroundColor: isActive ? ui.surfaceRaised : 'transparent',
                  borderColor: isActive ? ui.borderStrong : 'transparent',
                },
              ]}
              onPress={() => navigateToFolder(folder.id)}
              accessibilityRole="button"
              accessibilityLabel={`Open ${folder.label} folder`}
              accessibilityState={{ selected: isActive }}
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

        <View style={[styles.sectionDivider, { backgroundColor: ui.borderSubtle }]} />

        <Pressable
          style={[
            styles.folderRow,
            {
              backgroundColor: searchActive ? ui.surfaceRaised : 'transparent',
              borderColor: searchActive ? ui.borderStrong : 'transparent',
            },
          ]}
          onPress={() => navigateToRoute('/search')}
          accessibilityRole="button"
          accessibilityLabel="Open search"
        >
          <Search width={20} height={20} color={colors.mutedForeground} />
          <Text style={[styles.folderLabel, { color: colors.mutedForeground }]}>Search</Text>
        </Pressable>

        <Pressable
          style={[
            styles.folderRow,
            {
              backgroundColor: assistantActive ? ui.surfaceRaised : 'transparent',
              borderColor: assistantActive ? ui.borderStrong : 'transparent',
            },
          ]}
          onPress={() => navigateToRoute('/(app)/assistant')}
          accessibilityRole="button"
          accessibilityLabel="Open assistant"
        >
          <Sparkles width={20} height={20} color={colors.mutedForeground} />
          <Text style={[styles.folderLabel, { color: colors.mutedForeground }]}>Assistant</Text>
        </Pressable>

        <Pressable
          style={[
            styles.folderRow,
            {
              backgroundColor: settingsActive ? ui.surfaceRaised : 'transparent',
              borderColor: settingsActive ? ui.borderStrong : 'transparent',
            },
          ]}
          onPress={() => navigateToRoute('/(app)/settings')}
          accessibilityRole="button"
          accessibilityLabel="Open settings"
        >
          <Settings width={20} height={20} color={colors.mutedForeground} />
          <Text style={[styles.folderLabel, { color: colors.mutedForeground }]}>Settings</Text>
        </Pressable>
      </ScrollView>

      {session && (
        <View style={[styles.footer, { borderTopColor: ui.borderSubtle }]}>
          <Pressable
            style={[
              styles.logoutRow,
              { backgroundColor: ui.surfaceRaised, borderColor: ui.borderSubtle },
            ]}
            onPress={handleLogout}
            accessibilityRole="button"
            accessibilityLabel="Sign out"
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
    marginHorizontal: 14,
    marginTop: 10,
    marginBottom: 12,
    paddingHorizontal: 16,
    paddingVertical: 16,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 24,
    gap: 2,
  },
  headerEyebrow: {
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 0.6,
    textTransform: 'uppercase',
  },
  headerText: {
    fontSize: 24,
    fontWeight: '700',
    letterSpacing: -0.6,
  },
  headerSubtext: {
    fontSize: 12,
    lineHeight: 17,
  },
  scrollContainer: {
    flex: 1,
  },
  scrollContent: {
    paddingHorizontal: 10,
    paddingBottom: 16,
  },
  folderRow: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: StyleSheet.hairlineWidth,
    paddingVertical: 11,
    paddingHorizontal: 14,
    borderRadius: 16,
    marginBottom: 4,
  },
  folderLabel: {
    fontSize: 14,
    lineHeight: 18,
    marginLeft: 14,
    flex: 1,
  },
  sectionDivider: {
    height: StyleSheet.hairlineWidth,
    marginVertical: 14,
    marginHorizontal: 16,
  },
  footer: {
    padding: 14,
    borderTopWidth: StyleSheet.hairlineWidth,
  },
  logoutRow: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 16,
    gap: 12,
    paddingVertical: 10,
    paddingHorizontal: 12,
  },
  logoutText: {
    fontSize: 14,
    fontWeight: '500',
  },
});

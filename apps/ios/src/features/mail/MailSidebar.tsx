/**
 * MailSidebar — drawer content showing account controls, mail folders, settings link, and logout.
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
  Check,
  Plus,
  Pencil,
} from 'lucide-react-native';
import {
  View,
  Text,
  StyleSheet,
  Pressable,
  ScrollView,
  ActivityIndicator,
  Alert,
} from 'react-native';
import { sessionAtom, clearSessionAtom, setBearerSessionAtom } from '../../shared/state/session';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { getLinkSocialAuthUrl, parseAuthCallback } from '../auth/native-auth';
import { useRouter, useGlobalSearchParams, usePathname } from 'expo-router';
import { fetchAutumnCustomer } from '../../shared/integrations/autumn';
import { DrawerContentComponentProps } from '@react-navigation/drawer';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import React, { useCallback, useMemo, useState } from 'react';
import { useTRPC } from '../../providers/QueryTrpcProvider';
import { useTheme } from '../../shared/theme/ThemeContext';
import { getNativeEnv } from '../../shared/config/env';
import { haptics } from '../../shared/utils/haptics';
import { typography } from '@zero/design-tokens';
import { useAtomValue, useSetAtom } from 'jotai';
import * as WebBrowser from 'expo-web-browser';
import { Image } from 'expo-image';

type FolderDef = {
  id: string;
  label: string;
  icon: (color: string) => React.ReactNode;
};

type FolderSection = {
  title: string;
  items: FolderDef[];
};

type SidebarConnection = {
  id: string;
  email?: string | null;
  name?: string | null;
  picture?: string | null;
  providerId?: string | null;
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

const FOLDER_SECTIONS: FolderSection[] = [
  {
    title: 'Core',
    items: FOLDERS.filter((folder) => ['inbox', 'draft', 'sent'].includes(folder.id)),
  },
  {
    title: 'Management',
    items: FOLDERS.filter((folder) =>
      ['starred', 'snoozed', 'archive', 'spam', 'bin'].includes(folder.id),
    ),
  },
];

function getConnectionTitle(connection: SidebarConnection | null): string {
  return connection?.name?.trim() || connection?.email?.trim() || 'Account';
}

function getConnectionInitials(connection: SidebarConnection | null): string {
  const source = getConnectionTitle(connection);
  const words = source.split(/\s+/).filter(Boolean);
  if (words.length >= 2) {
    return words
      .slice(0, 2)
      .map((word) => word[0]?.toUpperCase() ?? '')
      .join('');
  }

  const compact = source.replace(/[^A-Za-z0-9]/g, '');
  return compact.slice(0, 2).toUpperCase() || '?';
}

function AccountAvatar({
  connection,
  size,
  borderColor,
  backgroundColor,
  textColor,
}: {
  connection: SidebarConnection | null;
  size: number;
  borderColor: string;
  backgroundColor: string;
  textColor: string;
}) {
  const imageUri = connection?.picture?.trim() ?? '';

  return (
    <View
      style={[
        styles.avatar,
        {
          width: size,
          height: size,
          borderColor,
          backgroundColor,
          borderRadius: Math.max(12, size / 3.2),
        },
      ]}
    >
      {imageUri ? (
        <Image
          source={{ uri: imageUri }}
          style={StyleSheet.absoluteFillObject}
          contentFit="cover"
        />
      ) : (
        <Text
          style={[styles.avatarFallback, { color: textColor, fontSize: Math.max(12, size * 0.32) }]}
        >
          {getConnectionInitials(connection)}
        </Text>
      )}
    </View>
  );
}

export function MailSidebar(props: DrawerContentComponentProps) {
  const { colors, ui } = useTheme();
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const pathname = usePathname();
  const env = getNativeEnv();
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const session = useAtomValue(sessionAtom);
  const clearSession = useSetAtom(clearSessionAtom);
  const setBearerSession = useSetAtom(setBearerSessionAtom);
  const globalParams = useGlobalSearchParams();
  const activeFolder = (globalParams.folder as string) ?? 'inbox';
  const assistantActive = pathname.includes('/assistant');
  const settingsActive = pathname.includes('/settings');
  const searchActive = pathname === '/search';
  const bearerToken = session?.mode === 'bearer' ? session.token : null;
  const [linkingProviderId, setLinkingProviderId] = useState<string | null>(null);

  const connectionsQuery = useQuery({
    ...trpc.connections.list.queryOptions(),
    enabled: !!session && !env.authBypassEnabled,
    staleTime: 60_000,
    gcTime: 5 * 60_000,
  });
  const defaultConnectionQuery = useQuery({
    ...trpc.connections.getDefault.queryOptions(),
    enabled: !!session && !env.authBypassEnabled,
    staleTime: 60_000,
    gcTime: 5 * 60_000,
  });
  const setDefaultMutation = useMutation(trpc.connections.setDefault.mutationOptions());
  const billingQuery = useQuery({
    queryKey: ['autumn', 'customer', 'drawer-sidebar'],
    enabled: Boolean(bearerToken) && !env.authBypassEnabled,
    queryFn: () => fetchAutumnCustomer(env.backendUrl, bearerToken!),
    staleTime: 60_000,
    gcTime: 5 * 60_000,
  });

  const connections = useMemo(
    () =>
      (connectionsQuery.data as { connections?: SidebarConnection[] } | undefined)?.connections ??
      [],
    [connectionsQuery.data],
  );
  const disconnectedIds = useMemo(
    () =>
      new Set<string>(
        (connectionsQuery.data as { disconnectedIds?: string[] } | undefined)?.disconnectedIds ??
          [],
      ),
    [connectionsQuery.data],
  );
  const connectedConnections = useMemo(
    () => connections.filter((connection) => !disconnectedIds.has(connection.id)),
    [connections, disconnectedIds],
  );
  const disconnectedConnections = useMemo(
    () => connections.filter((connection) => disconnectedIds.has(connection.id)),
    [connections, disconnectedIds],
  );
  const activeConnection = useMemo(
    () =>
      (defaultConnectionQuery.data as SidebarConnection | null | undefined) ??
      connectedConnections[0] ??
      connections[0] ??
      null,
    [connectedConnections, connections, defaultConnectionQuery.data],
  );
  const connectionAllowance = billingQuery.data?.features?.connections;
  const canAddConnection =
    connections.length === 0 ||
    !connectionAllowance ||
    connectionAllowance.unlimited === true ||
    Number(connectionAllowance.balance ?? 0) > 0;
  const accountSectionLoading =
    Boolean(session) &&
    !env.authBypassEnabled &&
    (connectionsQuery.isLoading || defaultConnectionQuery.isLoading);

  const navigateToFolder = (folderId: string) => {
    router.push(`/(app)/(mail)/${folderId}` as any);
    props.navigation.closeDrawer();
  };

  const handleOpenCompose = useCallback(() => {
    haptics.selection();
    router.push('/compose');
    props.navigation.closeDrawer();
  }, [props.navigation, router]);

  const navigateToRoute = (
    nextPath:
      | '/search'
      | '/(app)/assistant'
      | '/(app)/settings'
      | '/(app)/settings/billing'
      | '/(app)/settings/connections',
  ) => {
    router.push(nextPath as any);
    props.navigation.closeDrawer();
  };

  const refreshAccountQueries = useCallback(async () => {
    await Promise.allSettled([
      queryClient.invalidateQueries({ queryKey: trpc.connections.list.queryKey() }),
      queryClient.invalidateQueries({ queryKey: trpc.connections.getDefault.queryKey() }),
      queryClient.invalidateQueries({ queryKey: trpc.settings.get.queryKey() }),
    ]);
  }, [queryClient, trpc]);

  const startLinkFlow = useCallback(
    async (providerId: string) => {
      if (!bearerToken) {
        navigateToRoute('/(app)/settings/connections');
        return;
      }

      const mobileTokenUrl = `${env.backendUrl.replace(/\/$/, '')}/api/auth/mobile-token`;
      setLinkingProviderId(providerId);

      try {
        haptics.selection();
        const authUrl = await getLinkSocialAuthUrl(
          env.backendUrl,
          env.webUrl,
          bearerToken,
          providerId,
          mobileTokenUrl,
        );
        const result = await WebBrowser.openAuthSessionAsync(authUrl, 'todus://auth-callback');

        if (result.type === 'cancel' || result.type === 'dismiss') {
          return;
        }

        const callback = result.type === 'success' ? parseAuthCallback(result.url) : null;
        if (callback?.token) {
          await setBearerSession({ token: callback.token, expiresAt: callback.expiresAt });
        }

        await refreshAccountQueries();
      } catch (error: any) {
        const message = error?.message || 'Could not connect another account.';
        if (/billing|plan|upgrade|limit/i.test(message)) {
          navigateToRoute('/(app)/settings/billing');
          return;
        }

        Alert.alert('Could not connect another account', message);
      } finally {
        setLinkingProviderId(null);
      }
    },
    [
      bearerToken,
      env.backendUrl,
      env.webUrl,
      navigateToRoute,
      refreshAccountQueries,
      setBearerSession,
    ],
  );

  const handleAddAccount = useCallback(() => {
    if (!canAddConnection) {
      navigateToRoute('/(app)/settings/billing');
      return;
    }

    void startLinkFlow('google');
  }, [canAddConnection, navigateToRoute, startLinkFlow]);

  const handleReconnect = useCallback(
    (providerId?: string | null) => {
      if (!providerId) {
        Alert.alert(
          'Reconnect unavailable',
          'This connection does not expose a supported provider.',
        );
        return;
      }

      void startLinkFlow(providerId);
    },
    [startLinkFlow],
  );

  const handleSwitchAccount = useCallback(
    async (connectionId: string) => {
      if (setDefaultMutation.isPending || connectionId === activeConnection?.id) return;

      try {
        haptics.selection();
        await setDefaultMutation.mutateAsync({ connectionId });
        queryClient.clear();
        props.navigation.closeDrawer();
      } catch (error: any) {
        await refreshAccountQueries();
        Alert.alert('Could not switch account', error?.message || 'Please try again.');
      }
    },
    [
      activeConnection?.id,
      props.navigation,
      queryClient,
      refreshAccountQueries,
      setDefaultMutation,
    ],
  );

  const handleLogout = async () => {
    await clearSession();
  };

  return (
    <View style={[styles.container, { backgroundColor: ui.canvas, paddingTop: insets.top }]}>
      <ScrollView style={styles.scrollContainer} contentContainerStyle={styles.scrollContent}>
        {session && (
          <View
            style={[
              styles.accountsCard,
              {
                backgroundColor: ui.surfaceRaised,
                borderColor: ui.borderSubtle,
              },
            ]}
          >
            <View style={styles.accountsHeaderRow}>
              <View style={styles.accountHeaderCluster}>
                <Text style={[styles.accountsEyebrow, { color: colors.mutedForeground }]}>
                  Accounts
                </Text>
                <View style={styles.accountSwitcherRow}>
                  {connectedConnections.map((connection) => {
                    const isActive = connection.id === activeConnection?.id;

                    return (
                      <Pressable
                        key={connection.id}
                        style={[
                          styles.accountChip,
                          {
                            borderColor: isActive ? ui.borderStrong : ui.borderSubtle,
                            backgroundColor: isActive ? ui.surfaceMuted : ui.surfaceInset,
                          },
                        ]}
                        onPress={() => handleSwitchAccount(connection.id)}
                        disabled={isActive || setDefaultMutation.isPending}
                        accessibilityRole="button"
                        accessibilityLabel={`Switch to ${connection.email || getConnectionTitle(connection)}`}
                        accessibilityState={{
                          selected: isActive,
                          disabled: isActive || setDefaultMutation.isPending,
                        }}
                      >
                        <AccountAvatar
                          connection={connection}
                          size={34}
                          borderColor="transparent"
                          backgroundColor={ui.avatar}
                          textColor={ui.avatarText}
                        />
                        {isActive && (
                          <View
                            style={[
                              styles.accountChipBadge,
                              { backgroundColor: colors.foreground, borderColor: ui.surfaceRaised },
                            ]}
                          >
                            <Check width={9} height={9} color={colors.background} />
                          </View>
                        )}
                      </Pressable>
                    );
                  })}

                  <Pressable
                    style={[
                      styles.accountChip,
                      {
                        borderColor: ui.borderSubtle,
                        backgroundColor: canAddConnection ? ui.surface : ui.surfaceInset,
                        opacity: linkingProviderId ? 0.7 : 1,
                      },
                    ]}
                    onPress={handleAddAccount}
                    disabled={Boolean(linkingProviderId)}
                    accessibilityRole="button"
                    accessibilityLabel={
                      canAddConnection
                        ? 'Add another email account'
                        : 'Open billing to add another email account'
                    }
                  >
                    {linkingProviderId ? (
                      <ActivityIndicator size="small" color={colors.foreground} />
                    ) : (
                      <Plus width={16} height={16} color={colors.foreground} />
                    )}
                  </Pressable>
                </View>
              </View>
              {accountSectionLoading && (
                <ActivityIndicator size="small" color={colors.mutedForeground} />
              )}
            </View>

            {activeConnection ? (
              <View style={styles.activeAccountRow}>
                <Text style={[styles.activeAccountName, { color: colors.foreground }]}>
                  {getConnectionTitle(activeConnection)}
                </Text>
                <Text style={[styles.activeAccountEmail, { color: colors.mutedForeground }]}>
                  {activeConnection.email || 'No email available'}
                </Text>
              </View>
            ) : (
              <Text style={[styles.emptyAccountsText, { color: colors.mutedForeground }]}>
                {env.authBypassEnabled
                  ? 'Accounts are unavailable while auth bypass mode is active.'
                  : 'No connected email accounts were found for this account.'}
              </Text>
            )}

            <Text style={[styles.switchHint, { color: colors.mutedForeground }]}>
              Tap an avatar to switch accounts.
            </Text>

            <Pressable
              style={({ pressed }) => [
                styles.composeButton,
                {
                  backgroundColor: pressed ? '#005FD6' : '#0A67E8',
                },
              ]}
              onPress={handleOpenCompose}
              accessibilityRole="button"
              accessibilityLabel="Compose new email"
            >
              <Pencil width={14} height={14} color="#FFFFFF" />
              <Text style={styles.composeButtonLabel}>New email</Text>
            </Pressable>

            {disconnectedConnections.length > 0 && (
              <View style={[styles.disconnectedSection, { borderTopColor: ui.borderSubtle }]}>
                <Text style={[styles.disconnectedTitle, { color: colors.mutedForeground }]}>
                  Reconnect
                </Text>
                {disconnectedConnections.map((connection) => {
                  const reconnecting = linkingProviderId === connection.providerId;

                  return (
                    <View
                      key={connection.id}
                      style={[
                        styles.disconnectedRow,
                        { backgroundColor: ui.surfaceInset, borderColor: ui.borderSubtle },
                      ]}
                    >
                      <View style={styles.disconnectedCopy}>
                        <Text style={[styles.disconnectedName, { color: colors.foreground }]}>
                          {getConnectionTitle(connection)}
                        </Text>
                        <Text style={[styles.disconnectedEmail, { color: colors.mutedForeground }]}>
                          {connection.email || 'Disconnected mailbox'}
                        </Text>
                      </View>
                      <Pressable
                        style={[
                          styles.reconnectButton,
                          { backgroundColor: ui.surface, borderColor: ui.borderStrong },
                        ]}
                        onPress={() => handleReconnect(connection.providerId)}
                        disabled={Boolean(linkingProviderId)}
                        accessibilityRole="button"
                        accessibilityLabel={`Reconnect ${connection.email || getConnectionTitle(connection)}`}
                      >
                        {reconnecting ? (
                          <ActivityIndicator size="small" color={colors.foreground} />
                        ) : (
                          <Text style={[styles.reconnectButtonText, { color: colors.foreground }]}>
                            Reconnect
                          </Text>
                        )}
                      </Pressable>
                    </View>
                  );
                })}
              </View>
            )}
          </View>
        )}

        {FOLDER_SECTIONS.map((section) => (
          <View key={section.title} style={styles.menuSection}>
            <Text style={[styles.menuSectionTitle, { color: colors.mutedForeground }]}>
              {section.title}
            </Text>
            {section.items.map((folder) => {
              const isActive = activeFolder === folder.id;
              return (
                <Pressable
                  key={folder.id}
                  style={({ pressed }) => [
                    styles.folderRow,
                    {
                      backgroundColor: isActive
                        ? ui.surfaceRaised
                        : pressed
                          ? ui.surfaceMuted
                          : 'transparent',
                      borderColor: 'transparent',
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
          </View>
        ))}

        <View style={[styles.sectionDivider, { backgroundColor: ui.borderSubtle }]} />

        <Pressable
          style={({ pressed }) => [
            styles.folderRow,
            {
              backgroundColor: searchActive
                ? ui.surfaceRaised
                : pressed
                  ? ui.surfaceMuted
                  : 'transparent',
              borderColor: 'transparent',
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
          style={({ pressed }) => [
            styles.folderRow,
            {
              backgroundColor: assistantActive
                ? ui.surfaceRaised
                : pressed
                  ? ui.surfaceMuted
                  : 'transparent',
              borderColor: 'transparent',
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
          style={({ pressed }) => [
            styles.folderRow,
            {
              backgroundColor: settingsActive
                ? ui.surfaceRaised
                : pressed
                  ? ui.surfaceMuted
                  : 'transparent',
              borderColor: 'transparent',
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
        <View
          style={[
            styles.footer,
            {
              borderTopColor: ui.borderSubtle,
              paddingBottom: Math.max(insets.bottom + 8, 18),
            },
          ]}
        >
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
  scrollContainer: {
    flex: 1,
  },
  scrollContent: {
    paddingHorizontal: 12,
    paddingBottom: 16,
  },
  accountsCard: {
    marginTop: 8,
    marginBottom: 12,
    paddingHorizontal: 13,
    paddingVertical: 13,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 18,
  },
  accountsHeaderRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    marginBottom: 10,
    gap: 10,
  },
  accountHeaderCluster: {
    flex: 1,
    gap: 8,
  },
  accountsEyebrow: {
    fontSize: 12,
    fontWeight: '600',
    letterSpacing: 0.2,
  },
  activeAccountRow: {
    gap: 2,
  },
  activeAccountName: {
    fontSize: 17,
    fontWeight: '600',
    lineHeight: 20,
  },
  activeAccountEmail: {
    fontSize: 13,
    lineHeight: 16,
  },
  emptyAccountsText: {
    fontSize: 13,
    lineHeight: 18,
  },
  accountSwitcherRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 7,
  },
  accountChip: {
    width: 42,
    height: 42,
    borderRadius: 13,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
    position: 'relative',
  },
  accountChipBadge: {
    position: 'absolute',
    right: 3,
    bottom: 3,
    width: 14,
    height: 14,
    borderRadius: 999,
    borderWidth: 2,
    alignItems: 'center',
    justifyContent: 'center',
  },
  switchHint: {
    marginTop: 10,
    fontSize: 12,
    lineHeight: 15,
  },
  disconnectedSection: {
    marginTop: 12,
    paddingTop: 12,
    borderTopWidth: StyleSheet.hairlineWidth,
    gap: 6,
  },
  disconnectedTitle: {
    fontSize: 12,
    fontWeight: '600',
    letterSpacing: 0.2,
  },
  disconnectedRow: {
    borderWidth: 0,
    borderRadius: 12,
    paddingHorizontal: 10,
    paddingVertical: 9,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  disconnectedCopy: {
    flex: 1,
    gap: 2,
  },
  disconnectedName: {
    fontSize: 13,
    fontWeight: '600',
  },
  disconnectedEmail: {
    fontSize: 12,
  },
  reconnectButton: {
    minWidth: 82,
    minHeight: 32,
    borderRadius: 10,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 10,
  },
  reconnectButtonText: {
    fontSize: 12,
    fontWeight: '600',
  },
  avatar: {
    overflow: 'hidden',
    borderWidth: 0,
    alignItems: 'center',
    justifyContent: 'center',
  },
  avatarFallback: {
    fontWeight: '700',
    letterSpacing: 0.2,
  },
  folderRow: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: StyleSheet.hairlineWidth,
    paddingVertical: 9,
    paddingHorizontal: 12,
    borderRadius: 14,
    marginBottom: 3,
  },
  folderLabel: {
    fontSize: 14,
    lineHeight: 18,
    marginLeft: 12,
    flex: 1,
  },
  composeButton: {
    minHeight: 36,
    borderRadius: 14,
    marginTop: 12,
    alignItems: 'center',
    justifyContent: 'center',
    flexDirection: 'row',
    gap: 8,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  composeButtonLabel: {
    color: '#FFFFFF',
    fontSize: 14,
    fontWeight: '600',
    lineHeight: 18,
  },
  menuSection: {
    marginBottom: 10,
  },
  menuSectionTitle: {
    fontSize: 12,
    fontWeight: '600',
    lineHeight: 15,
    marginBottom: 5,
    marginLeft: 3,
    letterSpacing: 0.1,
  },
  sectionDivider: {
    height: StyleSheet.hairlineWidth,
    marginVertical: 8,
    marginHorizontal: 4,
  },
  footer: {
    paddingHorizontal: 16,
    paddingTop: 12,
    borderTopWidth: StyleSheet.hairlineWidth,
  },
  logoutRow: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: 0,
    borderRadius: 14,
    gap: 10,
    paddingVertical: 9,
    paddingHorizontal: 14,
    alignSelf: 'stretch',
    justifyContent: 'center',
  },
  logoutText: {
    fontSize: 13,
    fontWeight: '600',
  },
});

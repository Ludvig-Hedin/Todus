/**
 * Connections settings — list, default selection, disconnect, and reconnect entry points.
 */
import {
  ScrollView,
  StyleSheet,
  Text,
  View,
  ActivityIndicator,
  Pressable,
  Alert,
  Linking,
} from 'react-native';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Mail, Star, Unplug, Trash2, Plus } from 'lucide-react-native';
import { useTRPC } from '../../../src/providers/QueryTrpcProvider';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '../../../src/shared/theme/ThemeContext';
import { getNativeEnv } from '../../../src/shared/config/env';
import { haptics } from '../../../src/shared/utils/haptics';
import { useMemo } from 'react';

export default function ConnectionsSettings() {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const env = getNativeEnv();

  const { data, isLoading } = useQuery(trpc.connections.list.queryOptions());
  const defaultConnectionQuery = useQuery(trpc.connections.getDefault.queryOptions());
  const defaultConnectionId = defaultConnectionQuery.data?.id ?? null;

  const setDefaultMutation = useMutation({
    ...trpc.connections.setDefault.mutationOptions(),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: trpc.connections.list.queryKey() });
      queryClient.invalidateQueries({ queryKey: trpc.connections.getDefault.queryKey() });
    },
  });
  const deleteMutation = useMutation({
    ...trpc.connections.delete.mutationOptions(),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: trpc.connections.list.queryKey() });
      queryClient.invalidateQueries({ queryKey: trpc.connections.getDefault.queryKey() });
    },
  });

  const connections = ((data as any)?.connections as any[]) ?? [];
  const disconnectedIds = useMemo(
    () => new Set<string>(((data as any)?.disconnectedIds as string[] | undefined) ?? []),
    [data],
  );

  const openConnectionsOnWeb = async () => {
    const url = `${env.webUrl.replace(/\/$/, '')}/settings/connections`;
    await Linking.openURL(url);
  };

  const setDefaultConnection = async (connectionId: string) => {
    try {
      haptics.selection();
      await setDefaultMutation.mutateAsync({ connectionId });
    } catch (error: any) {
      Alert.alert('Failed', error?.message || 'Could not set default connection.');
    }
  };

  const disconnectConnection = (connectionId: string) => {
    Alert.alert(
      'Disconnect account?',
      'The account will be removed from this device until you reconnect it.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Disconnect',
          style: 'destructive',
          onPress: async () => {
            try {
              haptics.warning();
              await deleteMutation.mutateAsync({ connectionId });
            } catch (error: any) {
              Alert.alert('Failed', error?.message || 'Could not disconnect account.');
            }
          },
        },
      ],
      { cancelable: true },
    );
  };

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <ScrollView contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + 16 }]}>
        <Text style={[styles.sectionTitle, { color: colors.foreground }]}>Connected Accounts</Text>

        {isLoading ? (
          <ActivityIndicator color={colors.primary} style={{ marginVertical: 24 }} />
        ) : connections.length === 0 ? (
          <View
            style={[
              styles.emptyState,
              { backgroundColor: colors.card, borderColor: colors.border },
            ]}
          >
            <Text style={[styles.emptyText, { color: colors.mutedForeground }]}>
              No email accounts connected.
            </Text>
          </View>
        ) : (
          <View
            style={[styles.section, { backgroundColor: colors.card, borderColor: colors.border }]}
          >
            {connections.map((conn: any, index: number) => (
              <View
                key={conn.id || index}
                style={[
                  styles.connectionItem,
                  index < connections.length - 1 && {
                    borderBottomWidth: StyleSheet.hairlineWidth,
                    borderBottomColor: colors.border,
                  },
                ]}
              >
                <Mail size={20} color={colors.mutedForeground} />
                <View style={styles.connectionInfo}>
                  <Text style={[styles.connectionEmail, { color: colors.foreground }]}>
                    {conn.email || conn.providerId || 'Unknown'}
                  </Text>
                  <View style={styles.metaRow}>
                    <Text style={[styles.connectionProvider, { color: colors.mutedForeground }]}>
                      {conn.providerId || 'Email'}
                    </Text>
                    {defaultConnectionId === conn.id && (
                      <Text style={[styles.badge, { color: colors.primary }]}>Default</Text>
                    )}
                    {disconnectedIds.has(conn.id) && (
                      <Text style={[styles.badge, { color: colors.destructive }]}>
                        Disconnected
                      </Text>
                    )}
                  </View>
                </View>
                <View style={styles.actions}>
                  <Pressable
                    style={[styles.iconButton, { borderColor: colors.border }]}
                    onPress={() => setDefaultConnection(conn.id)}
                    disabled={setDefaultMutation.isPending}
                  >
                    <Star size={16} color={colors.primary} />
                  </Pressable>
                  {disconnectedIds.has(conn.id) ? (
                    <Pressable
                      style={[styles.iconButton, { borderColor: colors.border }]}
                      onPress={openConnectionsOnWeb}
                    >
                      <Unplug size={16} color={colors.foreground} />
                    </Pressable>
                  ) : (
                    <Pressable
                      style={[styles.iconButton, { borderColor: colors.border }]}
                      onPress={() => disconnectConnection(conn.id)}
                      disabled={connections.length <= 1 || deleteMutation.isPending}
                    >
                      <Trash2 size={16} color={colors.destructive} />
                    </Pressable>
                  )}
                </View>
              </View>
            ))}
          </View>
        )}

        <Pressable
          style={[styles.addButton, { borderColor: colors.border, backgroundColor: colors.card }]}
          onPress={openConnectionsOnWeb}
        >
          <Plus size={16} color={colors.foreground} />
          <Text style={[styles.addButtonLabel, { color: colors.foreground }]}>
            Add Email Account
          </Text>
        </Pressable>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  content: { padding: 16 },
  sectionTitle: {
    fontSize: 14,
    fontWeight: '600',
    textTransform: 'uppercase',
    letterSpacing: 0.5,
    marginBottom: 8,
  },
  section: {
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  connectionItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 14,
    gap: 12,
  },
  connectionInfo: { flex: 1, gap: 2 },
  metaRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  connectionEmail: { fontSize: 16, fontWeight: '500' },
  connectionProvider: { fontSize: 13 },
  badge: { fontSize: 12, fontWeight: '600' },
  actions: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  iconButton: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 8,
    width: 30,
    height: 30,
    alignItems: 'center',
    justifyContent: 'center',
  },
  emptyState: {
    padding: 24,
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
  },
  emptyText: { fontSize: 14 },
  addButton: {
    marginTop: 12,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 10,
    paddingHorizontal: 14,
    paddingVertical: 12,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
  },
  addButtonLabel: { fontSize: 14, fontWeight: '600' },
});

/**
 * Connections settings — manage connected email accounts.
 */
import { ScrollView, StyleSheet, Text, View, ActivityIndicator } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '../../../src/shared/theme/ThemeContext';
import { useTRPC } from '../../../src/providers/QueryTrpcProvider';
import { useQuery } from '@tanstack/react-query';
import { Mail } from 'lucide-react-native';

export default function ConnectionsSettings() {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const trpc = useTRPC();

  const { data, isLoading } = useQuery(trpc.connections.list.queryOptions());

  const connections = ((data as any)?.connections as any[]) ?? [];

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <ScrollView contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + 16 }]}>
        <Text style={[styles.sectionTitle, { color: colors.foreground }]}>Connected Accounts</Text>

        {isLoading ? (
          <ActivityIndicator color={colors.primary} style={{ marginVertical: 24 }} />
        ) : connections.length === 0 ? (
          <View style={[styles.emptyState, { backgroundColor: colors.card, borderColor: colors.border }]}>
            <Text style={[styles.emptyText, { color: colors.mutedForeground }]}>
              No email accounts connected.
            </Text>
          </View>
        ) : (
          <View style={[styles.section, { backgroundColor: colors.card, borderColor: colors.border }]}>
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
                  <Text style={[styles.connectionProvider, { color: colors.mutedForeground }]}>
                    {conn.providerId || 'Email'}
                  </Text>
                </View>
              </View>
            ))}
          </View>
        )}
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
  connectionEmail: { fontSize: 16, fontWeight: '500' },
  connectionProvider: { fontSize: 13 },
  emptyState: {
    padding: 24,
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
  },
  emptyText: { fontSize: 14 },
});

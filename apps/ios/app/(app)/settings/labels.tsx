/**
 * Labels settings — manage custom email labels.
 */
import { ScrollView, StyleSheet, Text, View, ActivityIndicator } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '../../../src/shared/theme/ThemeContext';
import { useTRPC } from '../../../src/providers/QueryTrpcProvider';
import { useQuery } from '@tanstack/react-query';
import { Tag } from 'lucide-react-native';

export default function LabelsSettings() {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const trpc = useTRPC();

  const { data, isLoading } = useQuery(trpc.labels.list.queryOptions());

  const labels = (data as any[]) ?? [];

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <ScrollView contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + 16 }]}>
        <Text style={[styles.sectionTitle, { color: colors.foreground }]}>Labels</Text>

        {isLoading ? (
          <ActivityIndicator color={colors.primary} style={{ marginVertical: 24 }} />
        ) : labels.length === 0 ? (
          <View style={[styles.emptyState, { backgroundColor: colors.card, borderColor: colors.border }]}>
            <Text style={[styles.emptyText, { color: colors.mutedForeground }]}>
              No custom labels yet.
            </Text>
          </View>
        ) : (
          <View style={[styles.section, { backgroundColor: colors.card, borderColor: colors.border }]}>
            {labels.map((label: any, index: number) => (
              <View
                key={label.id || index}
                style={[
                  styles.labelItem,
                  index < labels.length - 1 && {
                    borderBottomWidth: StyleSheet.hairlineWidth,
                    borderBottomColor: colors.border,
                  },
                ]}
              >
                <Tag size={18} color={label.color || colors.mutedForeground} />
                <Text style={[styles.labelName, { color: colors.foreground }]}>
                  {label.name || 'Unnamed'}
                </Text>
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
  labelItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 14,
    gap: 12,
  },
  labelName: { fontSize: 16, fontWeight: '500' },
  emptyState: {
    padding: 24,
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
  },
  emptyText: { fontSize: 14 },
});

/**
 * General settings — timezone, language, default email alias.
 */
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '../../../src/shared/theme/ThemeContext';

export default function GeneralSettings() {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <ScrollView contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + 16 }]}>
        <View style={[styles.placeholder, { backgroundColor: colors.card, borderColor: colors.border }]}>
          <Text style={[styles.placeholderText, { color: colors.mutedForeground }]}>
            General settings (timezone, language, default email) will use tRPC settings.get/save mutations.
          </Text>
        </View>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  content: { padding: 16 },
  placeholder: {
    padding: 24,
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    gap: 8,
  },
  placeholderText: { fontSize: 14, textAlign: 'center' },
});

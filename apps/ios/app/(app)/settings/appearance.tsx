/**
 * Appearance settings — theme toggle (light/dark/system).
 */
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '../../../src/shared/theme/ThemeContext';
import { Sun, Moon, Smartphone } from 'lucide-react-native';
import { haptics } from '../../../src/shared/utils/haptics';

const THEMES = [
  { id: 'system', label: 'System', icon: Smartphone },
  { id: 'light', label: 'Light', icon: Sun },
  { id: 'dark', label: 'Dark', icon: Moon },
] as const;

export default function AppearanceSettings() {
  const { colors, colorMode } = useTheme();
  const insets = useSafeAreaInsets();

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <ScrollView contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + 16 }]}>
        <Text style={[styles.sectionTitle, { color: colors.foreground }]}>Theme</Text>
        <View style={[styles.section, { backgroundColor: colors.card, borderColor: colors.border }]}>
          {THEMES.map((theme, index) => {
            const isLast = index === THEMES.length - 1;
            const isActive = theme.id === 'system'; // Default to system for now
            const Icon = theme.icon;
            return (
              <Pressable
                key={theme.id}
                onPress={() => haptics.selection()}
                style={[
                  styles.themeItem,
                  !isLast && { borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: colors.border },
                ]}
              >
                <Icon size={20} color={isActive ? colors.primary : colors.mutedForeground} />
                <Text
                  style={[
                    styles.themeLabel,
                    { color: isActive ? colors.foreground : colors.mutedForeground },
                    isActive && { fontWeight: '600' },
                  ]}
                >
                  {theme.label}
                </Text>
                {isActive && (
                  <View style={[styles.activeIndicator, { backgroundColor: colors.primary }]} />
                )}
              </Pressable>
            );
          })}
        </View>
        <Text style={[styles.footnote, { color: colors.mutedForeground }]}>
          Currently using {colorMode} mode. Theme persistence will be added in a future update.
        </Text>
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
  themeItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 14,
    gap: 12,
  },
  themeLabel: {
    fontSize: 16,
    flex: 1,
  },
  activeIndicator: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  footnote: {
    fontSize: 13,
    marginTop: 8,
    paddingHorizontal: 4,
  },
});

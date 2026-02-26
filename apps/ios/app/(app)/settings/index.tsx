/**
 * Settings hub — lists all settings sections with navigation to detail pages.
 */
import { useRouter } from 'expo-router';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '../../../src/shared/theme/ThemeContext';
import {
  Settings,
  Palette,
  Link,
  Tag,
} from 'lucide-react-native';

const SETTINGS_ITEMS = [
  { key: 'general', label: 'General', description: 'Account preferences', icon: Settings },
  { key: 'appearance', label: 'Appearance', description: 'Theme & display', icon: Palette },
  { key: 'connections', label: 'Connections', description: 'Email accounts', icon: Link },
  { key: 'labels', label: 'Labels', description: 'Manage labels', icon: Tag },
] as const;

export default function SettingsIndex() {
  const router = useRouter();
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <ScrollView contentContainerStyle={[styles.content, { paddingTop: insets.top + 16, paddingBottom: insets.bottom + 16 }]}>
        <Text style={[styles.title, { color: colors.foreground }]}>Settings</Text>

        <View style={[styles.section, { backgroundColor: colors.card, borderColor: colors.border }]}>
          {SETTINGS_ITEMS.map((item, index) => {
            const isLast = index === SETTINGS_ITEMS.length - 1;
            const Icon = item.icon;
            return (
              <Pressable
                key={item.key}
                style={[
                  styles.settingsItem,
                  !isLast && { borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: colors.border },
                ]}
                onPress={() => router.push(`/(app)/settings/${item.key}` as any)}
              >
                <Icon size={20} color={colors.mutedForeground} />
                <View style={styles.settingsItemContent}>
                  <Text style={[styles.settingsItemLabel, { color: colors.foreground }]}>
                    {item.label}
                  </Text>
                  <Text style={[styles.settingsItemDescription, { color: colors.mutedForeground }]}>
                    {item.description}
                  </Text>
                </View>
                <Text style={[styles.chevron, { color: colors.mutedForeground }]}>&rsaquo;</Text>
              </Pressable>
            );
          })}
        </View>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  content: {
    padding: 16,
  },
  title: {
    fontSize: 28,
    fontWeight: '800',
    letterSpacing: -0.5,
    marginBottom: 20,
    marginTop: 8,
  },
  section: {
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  settingsItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 14,
    gap: 12,
  },
  settingsItemContent: {
    flex: 1,
    gap: 2,
  },
  settingsItemLabel: {
    fontSize: 16,
    fontWeight: '500',
  },
  settingsItemDescription: {
    fontSize: 13,
  },
  chevron: {
    fontSize: 22,
    fontWeight: '300',
    marginLeft: 8,
  },
});

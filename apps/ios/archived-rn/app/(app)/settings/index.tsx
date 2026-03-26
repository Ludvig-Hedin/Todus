/**
 * Settings hub — lists all settings sections with navigation to detail pages.
 */
import {
  Settings,
  Palette,
  Link,
  Tag,
  Bell,
  Lock,
  AlertTriangle,
  Grid2x2,
  Keyboard,
  ChevronLeft,
  Menu,
  Banknote,
} from 'lucide-react-native';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '../../../src/shared/theme/ThemeContext';
import { typography } from '@zero/design-tokens';
import { useNavigation, useRouter } from 'expo-router';

const SETTINGS_ITEMS = [
  { key: 'general', label: 'General', description: 'Account preferences', icon: Settings },
  { key: 'appearance', label: 'Appearance', description: 'Theme & display', icon: Palette },
  { key: 'connections', label: 'Connections', description: 'Email accounts', icon: Link },
  { key: 'billing', label: 'Billing', description: 'Plans and invoices', icon: Banknote },
  { key: 'labels', label: 'Labels', description: 'Manage labels', icon: Tag },
  { key: 'categories', label: 'Categories', description: 'Inbox category views', icon: Grid2x2 },
  {
    key: 'notifications',
    label: 'Notifications',
    description: 'Email notification preferences',
    icon: Bell,
  },
  {
    key: 'privacy',
    label: 'Privacy',
    description: 'Image loading and trusted senders',
    icon: Lock,
  },
  { key: 'security', label: 'Security', description: 'Account protection options', icon: Lock },
  {
    key: 'shortcuts',
    label: 'Shortcuts',
    description: 'Keyboard shortcut reference',
    icon: Keyboard,
  },
  {
    key: 'danger-zone',
    label: 'Danger Zone',
    description: 'Destructive account actions',
    icon: AlertTriangle,
  },
] as const;

export default function SettingsIndex() {
  const router = useRouter();
  const navigation = useNavigation();
  const { colors, ui } = useTheme();
  const insets = useSafeAreaInsets();

  const goBackToMail = () => {
    if (router.canGoBack()) {
      router.back();
      return;
    }
    router.replace('/(app)/(mail)/inbox');
  };

  return (
    <View style={[styles.container, { backgroundColor: ui.canvas }]}>
      <ScrollView
        contentContainerStyle={[
          styles.content,
          { paddingTop: insets.top + 16, paddingBottom: insets.bottom + 16 },
        ]}
      >
        <View style={styles.topActions}>
          <Pressable
            style={[
              styles.topActionButton,
              { borderColor: ui.borderSubtle, backgroundColor: ui.surface },
            ]}
            onPress={goBackToMail}
            accessibilityRole="button"
            accessibilityLabel="Back to mail"
          >
            <ChevronLeft size={16} color={colors.foreground} />
            <Text style={[styles.topActionText, { color: colors.foreground }]}>Mail</Text>
          </Pressable>
          <Pressable
            style={[
              styles.topActionButton,
              { borderColor: ui.borderSubtle, backgroundColor: ui.surface },
            ]}
            onPress={() =>
              (navigation as any).openDrawer?.() ?? navigation.dispatch({ type: 'OPEN_DRAWER' })
            }
            accessibilityRole="button"
            accessibilityLabel="Open app menu"
          >
            <Menu size={16} color={colors.foreground} />
            <Text style={[styles.topActionText, { color: colors.foreground }]}>Menu</Text>
          </Pressable>
        </View>

        <View
          style={[
            styles.heroCard,
            { backgroundColor: ui.surfaceRaised, borderColor: ui.borderSubtle },
          ]}
        >
          <Text style={[styles.eyebrow, { color: colors.mutedForeground }]}>Preferences</Text>
          <Text style={[styles.title, { color: colors.foreground }]}>Settings</Text>
          <Text style={[styles.subtitle, { color: colors.mutedForeground }]}>
            Tune appearance, controls, and account behavior.
          </Text>
        </View>

        <View
          style={[
            styles.section,
            { backgroundColor: ui.surfaceRaised, borderColor: ui.borderSubtle },
          ]}
        >
          {SETTINGS_ITEMS.map((item, index) => {
            const isLast = index === SETTINGS_ITEMS.length - 1;
            const Icon = item.icon;
            return (
              <Pressable
                key={item.key}
                style={[
                  styles.settingsItem,
                  !isLast && {
                    borderBottomWidth: StyleSheet.hairlineWidth,
                    borderBottomColor: ui.borderSubtle,
                  },
                ]}
                onPress={() => router.push(`/(app)/settings/${item.key}` as any)}
                accessibilityRole="button"
                accessibilityLabel={`${item.label}. ${item.description}.`}
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
  topActions: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: 12,
    marginBottom: 10,
  },
  topActionButton: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 7,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  topActionText: {
    fontSize: typography.size.xs,
    fontWeight: '600',
  },
  heroCard: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 24,
    paddingHorizontal: 16,
    paddingVertical: 18,
    marginBottom: 16,
    gap: 2,
  },
  eyebrow: {
    fontSize: typography.size.xs,
    fontWeight: '700',
    letterSpacing: 0.6,
    textTransform: 'uppercase',
  },
  title: {
    fontSize: typography.size['2xl'],
    fontWeight: '700',
    letterSpacing: -0.6,
  },
  subtitle: {
    fontSize: typography.size.xs,
    lineHeight: 17,
  },
  section: {
    borderRadius: 22,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  settingsItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 15,
    gap: 12,
  },
  settingsItemContent: {
    flex: 1,
    gap: 2,
  },
  settingsItemLabel: {
    fontSize: typography.size.sm,
    fontWeight: '500',
  },
  settingsItemDescription: {
    fontSize: typography.size.xs,
    lineHeight: 16,
  },
  chevron: {
    fontSize: typography.size.xl,
    fontWeight: '300',
    marginLeft: 8,
  },
});

/**
 * Settings group layout — stack navigator for settings hub and individual pages.
 */
import { useTheme } from '../../../src/shared/theme/ThemeContext';
import { typography } from '@zero/design-tokens';
import { Stack } from 'expo-router';

export default function SettingsLayout() {
  const { colors, ui, isDark } = useTheme();

  return (
    <Stack
      screenOptions={{
        headerStyle: { backgroundColor: ui.canvas },
        headerTintColor: colors.foreground,
        statusBarStyle: isDark ? 'light' : 'dark',
        headerBackButtonDisplayMode: 'minimal',
        headerShadowVisible: false,
        headerTitleStyle: {
          fontSize: typography.size.md,
          fontWeight: '700',
        },
        contentStyle: { backgroundColor: ui.canvas },
      }}
    >
      <Stack.Screen name="index" options={{ headerShown: false }} />
      <Stack.Screen name="general" options={{ title: 'General' }} />
      <Stack.Screen name="appearance" options={{ title: 'Appearance' }} />
      <Stack.Screen name="connections" options={{ title: 'Connections' }} />
      <Stack.Screen name="labels" options={{ title: 'Labels' }} />
      <Stack.Screen name="billing" options={{ title: 'Billing' }} />
      <Stack.Screen name="categories" options={{ title: 'Categories' }} />
      <Stack.Screen name="notifications" options={{ title: 'Notifications' }} />
      <Stack.Screen name="privacy" options={{ title: 'Privacy' }} />
      <Stack.Screen name="security" options={{ title: 'Security' }} />
      <Stack.Screen name="shortcuts" options={{ title: 'Shortcuts' }} />
      <Stack.Screen name="danger-zone" options={{ title: 'Danger Zone' }} />
    </Stack>
  );
}

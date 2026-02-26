/**
 * Settings group layout — stack navigator for settings hub and individual pages.
 */
import { Stack } from 'expo-router';
import { useTheme } from '../../../src/shared/theme/ThemeContext';

export default function SettingsLayout() {
  const { colors } = useTheme();

  return (
    <Stack
      screenOptions={{
        headerStyle: { backgroundColor: colors.background },
        headerTintColor: colors.foreground,
        contentStyle: { backgroundColor: colors.background },
      }}
    >
      <Stack.Screen name="index" options={{ headerShown: false }} />
      <Stack.Screen name="general" options={{ title: 'General' }} />
      <Stack.Screen name="appearance" options={{ title: 'Appearance' }} />
      <Stack.Screen name="connections" options={{ title: 'Connections' }} />
      <Stack.Screen name="labels" options={{ title: 'Labels' }} />
    </Stack>
  );
}

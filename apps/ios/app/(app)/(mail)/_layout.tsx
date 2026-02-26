/**
 * Mail group layout — stack navigator for folder list and thread detail.
 */
import { Stack } from 'expo-router';
import { useTheme } from '../../../src/shared/theme/ThemeContext';

export default function MailLayout() {
  const { colors } = useTheme();

  return (
    <Stack
      screenOptions={{
        headerShown: false,
        contentStyle: { backgroundColor: colors.background },
      }}
    >
      <Stack.Screen name="[folder]" />
      <Stack.Screen name="thread/[threadId]" />
    </Stack>
  );
}

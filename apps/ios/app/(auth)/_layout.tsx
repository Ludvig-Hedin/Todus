/**
 * Auth group layout — stack navigator for login and OAuth callback screens.
 */
import { Stack } from 'expo-router';

export default function AuthLayout() {
  return (
    <Stack>
      <Stack.Screen name="login" options={{ title: 'Login' }} />
      <Stack.Screen name="web-auth" options={{ headerShown: false }} />
    </Stack>
  );
}

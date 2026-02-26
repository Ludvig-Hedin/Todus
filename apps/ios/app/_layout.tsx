/**
 * Root layout — wraps all routes with providers and handles auth guard redirects.
 * Expo Router auto-renders this as the outermost layout.
 */
import { Stack, useRouter, useSegments } from 'expo-router';
import { useAtomValue } from 'jotai';
import { useEffect } from 'react';
import { ActivityIndicator, StyleSheet, Text, View, useColorScheme } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { semanticColors } from '@zero/design-tokens';
import { AppProviders } from '../src/providers/AppProviders';
import { authStatusAtom } from '../src/shared/state/session';
import { ErrorBoundary } from '../src/shared/components/ErrorBoundary';

function AuthGuard() {
  const authStatus = useAtomValue(authStatusAtom);
  const segments = useSegments();
  const router = useRouter();
  const systemColorScheme = useColorScheme();
  const isDark = systemColorScheme === 'dark';
  const colors = isDark ? semanticColors.dark : semanticColors.light;

  useEffect(() => {
    if (authStatus === 'bootstrapping') return;

    const inAuthGroup = segments[0] === '(auth)';

    if (authStatus === 'unauthenticated' && !inAuthGroup) {
      router.replace('/(auth)/login');
    } else if (authStatus === 'authenticated' && inAuthGroup) {
      router.replace('/(app)/(mail)/inbox');
    }
  }, [authStatus, segments, router]);

  // Show loading screen while bootstrapping session
  if (authStatus === 'bootstrapping') {
    return (
      <View style={[styles.bootScreen, { backgroundColor: colors.background }]}>
        <ActivityIndicator size="large" color={colors.primary} />
        <Text style={[styles.bootText, { color: colors.mutedForeground }]}>Loading...</Text>
      </View>
    );
  }

  return (
    <Stack screenOptions={{ headerShown: false }}>
      <Stack.Screen name="(auth)" />
      <Stack.Screen name="(app)" />
      <Stack.Screen name="compose" options={{ presentation: 'modal' }} />
      <Stack.Screen name="search" options={{ presentation: 'modal' }} />
    </Stack>
  );
}

export default function RootLayout() {
  const systemColorScheme = useColorScheme();
  const isDark = systemColorScheme === 'dark';

  return (
    <ErrorBoundary>
      <AppProviders>
        <StatusBar style={isDark ? 'light' : 'dark'} />
        <AuthGuard />
      </AppProviders>
    </ErrorBoundary>
  );
}

const styles = StyleSheet.create({
  bootScreen: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
  },
  bootText: {
    fontSize: 14,
  },
});

/**
 * Root layout — wraps all routes with providers and handles auth guard redirects.
 * Expo Router auto-renders this as the outermost layout.
 */
import { ActivityIndicator, StyleSheet, Text, View, useColorScheme } from 'react-native';
import { Stack, usePathname, useRouter, useSegments } from 'expo-router';
import { ErrorBoundary } from '../src/shared/components/ErrorBoundary';
import { captureScreen } from '../src/shared/telemetry/posthog';
import { AppProviders } from '../src/providers/AppProviders';
import { authStatusAtom } from '../src/shared/state/session';
import { semanticColors } from '@zero/design-tokens';
import * as Sentry from '@sentry/react-native';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useRef } from 'react';
import { useAtomValue } from 'jotai';

function AuthGuard() {
  const authStatus = useAtomValue(authStatusAtom);
  const segments = useSegments();
  const pathname = usePathname();
  const router = useRouter();
  const systemColorScheme = useColorScheme();
  const isDark = systemColorScheme === 'dark';
  const colors = isDark ? semanticColors.dark : semanticColors.light;
  const lastTrackedPathRef = useRef<string | null>(null);

  useEffect(() => {
    if (authStatus === 'bootstrapping') return;

    const inAuthGroup = segments[0] === '(auth)';
    const inPublicGroup = segments[0] === '(public)';
    const inAppGroup = segments[0] === '(app)';
    const inApiGroup = segments[0] === 'api';
    const inAllowedModalRoute = segments[0] === 'compose' || segments[0] === 'search';

    if (authStatus === 'unauthenticated' && !inAuthGroup && !inPublicGroup && !inApiGroup) {
      router.replace('/(public)/home');
    } else if (
      authStatus === 'authenticated' &&
      (inAuthGroup || inPublicGroup || (!inAppGroup && !inAllowedModalRoute && !inApiGroup))
    ) {
      router.replace('/(app)/(mail)/inbox');
    }
  }, [authStatus, segments, router]);

  useEffect(() => {
    if (!pathname) return;
    if (lastTrackedPathRef.current === pathname) return;
    lastTrackedPathRef.current = pathname;

    captureScreen(pathname, {
      path: pathname,
      auth_status: authStatus,
      segment_root: segments[0] ?? null,
    });
  }, [authStatus, pathname, segments]);

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
      <Stack.Screen name="(public)" />
      <Stack.Screen name="(app)" />
      <Stack.Screen name="api/mailto-handler" />
      <Stack.Screen name="compose" options={{ presentation: 'modal' }} />
      <Stack.Screen name="search" options={{ presentation: 'modal' }} />
    </Stack>
  );
}

function RootLayout() {
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

export default Sentry.wrap(RootLayout);

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

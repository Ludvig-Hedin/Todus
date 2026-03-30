/**
 * AppProviders — root provider hierarchy.
 * Wraps all screens with theme, Jotai state, TRPC/React Query, and session management.
 */
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { ThemeProvider } from '../shared/theme/ThemeContext';
import { initPostHog } from '../shared/telemetry/posthog';
import { initSentry } from '../shared/telemetry/sentry';
import { QueryTrpcProvider } from './QueryTrpcProvider';
import { SessionBootstrap } from './SessionBootstrap';
import { getNativeEnv } from '../shared/config/env';
import { Provider as JotaiProvider } from 'jotai';
import type { PropsWithChildren } from 'react';
import { useEffect } from 'react';

export function AppProviders({ children }: PropsWithChildren) {
  const env = getNativeEnv();

  useEffect(() => {
    initPostHog({
      apiKey: env.posthogKey,
      host: env.posthogHost,
    });
    initSentry({
      dsn: env.sentryDsn,
      tunnel: `${env.backendUrl.replace(/\/$/, '')}/monitoring/sentry`,
    });
  }, [env.backendUrl, env.posthogHost, env.posthogKey, env.sentryDsn]);

  return (
    <SafeAreaProvider>
      <ThemeProvider>
        <JotaiProvider>
          <QueryTrpcProvider>
            <SessionBootstrap>{children}</SessionBootstrap>
          </QueryTrpcProvider>
        </JotaiProvider>
      </ThemeProvider>
    </SafeAreaProvider>
  );
}

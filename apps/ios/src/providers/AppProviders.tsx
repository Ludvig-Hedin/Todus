/**
 * AppProviders — root provider hierarchy.
 * Wraps all screens with theme, Jotai state, TRPC/React Query, and session management.
 */
import { Provider as JotaiProvider } from 'jotai';
import type { PropsWithChildren } from 'react';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { ThemeProvider } from '../shared/theme/ThemeContext';
import { QueryTrpcProvider } from './QueryTrpcProvider';
import { SessionBootstrap } from './SessionBootstrap';

export function AppProviders({ children }: PropsWithChildren) {
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

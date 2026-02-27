import { Provider as JotaiProvider } from 'jotai';
import type { PropsWithChildren } from 'react';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { ThemeProvider } from '../../shared/theme/ThemeContext';
import { QueryTrpcProvider } from './QueryTrpcProvider';
import { SessionBootstrap } from './SessionBootstrap';

/**
 * AppProviders — root provider hierarchy for the native app.
 * ThemeProvider wraps all screens so they can access design tokens via useTheme().
 */
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

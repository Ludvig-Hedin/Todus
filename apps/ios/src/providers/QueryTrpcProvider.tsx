/**
 * TRPC + React Query provider with offline cache persistence.
 * Reads Bearer token from secure storage and attaches to all API requests.
 */
import { createAsyncStoragePersister } from '@tanstack/query-async-storage-persister';
import { PersistQueryClientProvider } from '@tanstack/react-query-persist-client';
import { createZeroTrpcClient, type AppRouter } from '@zero/api-client';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { captureSentryException } from '../shared/telemetry/sentry';
import { secureStorage } from '../shared/storage/secure-storage';
import { QueryCache, QueryClient } from '@tanstack/react-query';
import { createTRPCContext } from '@trpc/tanstack-react-query';
import { useState, type PropsWithChildren } from 'react';
import { getNativeEnv } from '../shared/config/env';

const CACHE_BUSTER = 'native-expo-router-v1';

export const { TRPCProvider, useTRPC, useTRPCClient } = createTRPCContext<AppRouter>();

export function QueryTrpcProvider({ children }: PropsWithChildren) {
  const env = getNativeEnv();
  const [queryClient] = useState(
    () =>
      new QueryClient({
        queryCache: new QueryCache({
          onError: (error) => {
            const message = error instanceof Error ? error.message : String(error);
            const isUnauthorizedError = message.toUpperCase().includes('UNAUTHORIZED');

            if (env.authBypassEnabled && isUnauthorizedError) {
              return;
            }

            console.error('[native-query-error]', error);
            captureSentryException(error, { source: 'react-query.queryCache' });
          },
        }),
        defaultOptions: {
          queries: {
            retry: false,
            refetchOnWindowFocus: false,
            staleTime: 30_000,
            gcTime: 5 * 60_000,
          },
          mutations: { retry: false },
        },
      }),
  );
  const [trpcClient] = useState(() =>
    createZeroTrpcClient<AppRouter>({
      baseUrl: env.backendUrl,
      maxItems: 100,
      async getHeaders() {
        let session = null;
        try {
          session = await secureStorage.getSession();
        } catch {
          session = null;
        }

        if (!session || session.mode !== 'bearer' || !session.token) {
          return undefined;
        }
        return {
          Authorization: `Bearer ${session.token}`,
        };
      },
      includeCredentials: false,
    }),
  );
  const [persister] = useState(() =>
    createAsyncStoragePersister({
      storage: AsyncStorage,
      key: 'zero-native-query-cache',
    }),
  );

  return (
    <PersistQueryClientProvider
      client={queryClient as any}
      persistOptions={{
        persister,
        buster: CACHE_BUSTER,
      }}
    >
      <TRPCProvider trpcClient={trpcClient as any} queryClient={queryClient as any}>
        {children}
      </TRPCProvider>
    </PersistQueryClientProvider>
  );
}

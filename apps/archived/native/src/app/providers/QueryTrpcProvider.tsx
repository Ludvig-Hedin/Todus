import AsyncStorage from '@react-native-async-storage/async-storage';
import { createAsyncStoragePersister } from '@tanstack/query-async-storage-persister';
import { QueryCache, QueryClient } from '@tanstack/react-query';
import { PersistQueryClientProvider } from '@tanstack/react-query-persist-client';
import { createTRPCContext } from '@trpc/tanstack-react-query';
import { createZeroTrpcClient, type AppRouter } from '@zero/api-client';
import { useState, type PropsWithChildren } from 'react';
import { getNativeEnv } from '../../shared/config/env';
import { secureStorage } from '../../shared/storage/secure-storage';

const CACHE_BUSTER = 'native-m1-foundations';

export const { TRPCProvider, useTRPC, useTRPCClient } = createTRPCContext<AppRouter>();

export function QueryTrpcProvider({ children }: PropsWithChildren) {
  const env = getNativeEnv();
  const [queryClient] = useState(
    () =>
      new QueryClient({
        queryCache: new QueryCache({
          onError: (error) => {
            console.error('[native-query-error]', error);
          },
        }),
        defaultOptions: {
          queries: { retry: false, refetchOnWindowFocus: false },
          mutations: { retry: false },
        },
      }),
  );
  const [trpcClient] = useState(() =>
    createZeroTrpcClient<AppRouter>({
      baseUrl: env.backendUrl,
      maxItems: 100,
      async getHeaders() {
        const session = await secureStorage.getSession();
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
      <TRPCProvider trpcClient={trpcClient} queryClient={queryClient as any}>
        {children}
      </TRPCProvider>
    </PersistQueryClientProvider>
  );
}

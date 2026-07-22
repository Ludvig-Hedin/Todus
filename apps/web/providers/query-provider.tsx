import {
  PersistQueryClientProvider,
  type PersistedClient,
  type Persister,
} from '@tanstack/react-query-persist-client';
import { QueryCache, QueryClient, hashKey, type InfiniteData } from '@tanstack/react-query';
import { createTRPCContext } from '@trpc/tanstack-react-query';
import { createTRPCClient, httpBatchLink } from '@trpc/client';
import { useMemo, type PropsWithChildren } from 'react';
import type { AppRouter } from '@zero/server/trpc';
import { CACHE_BURST_KEY } from '@/lib/constants';
import { signOut } from '@/lib/auth-client';
import { get, set, del } from 'idb-keyval';
import superjson from 'superjson';

// CR-001: Guard with import.meta.env.DEV so Vite tree-shakes the bypass in production builds
const parityAuthBypass =
  import.meta.env.DEV &&
  (String(import.meta.env.VITE_PUBLIC_PARITY_AUTH_BYPASS ?? '').toLowerCase() === '1' ||
    String(import.meta.env.VITE_PUBLIC_PARITY_AUTH_BYPASS ?? '').toLowerCase() === 'true');

function createIDBPersister(idbValidKey: IDBValidKey = 'zero-query-cache') {
  return {
    persistClient: async (client: PersistedClient) => {
      await set(idbValidKey, client);
    },
    restoreClient: async () => {
      return await get<PersistedClient>(idbValidKey);
    },
    removeClient: async () => {
      await del(idbValidKey);
    },
  } satisfies Persister;
}

export const makeQueryClient = (connectionId: string | null) =>
  new QueryClient({
    queryCache: new QueryCache({
      onError: (err, { meta }) => {
        if (meta && meta.noGlobalError === true) return;
        if (meta && typeof meta.customError === 'string') console.error(meta.customError);
        else if (
          err.message === 'Required scopes missing' ||
          err.message.includes('Invalid connection')
        ) {
          if (parityAuthBypass) return;
          signOut({
            fetchOptions: {
              onSuccess: () => {
                if (window.location.href.includes('/login')) return;
                window.location.href = '/login?error=required_scopes_missing';
              },
            },
          });
        } else console.error(err.message || 'Something went wrong');
      },
    }),
    defaultOptions: {
      queries: {
        retry: false,
        refetchOnWindowFocus: false,
        queryKeyHashFn: (queryKey) => hashKey([{ connectionId }, ...queryKey]),
        gcTime: 1000 * 60 * 60 * 24, // 24 hours,
        networkMode: 'offlineFirst', // serve IDB cache immediately, fetch in background
      },
      mutations: {
        onError: (err) => console.error(err.message),
        networkMode: 'offlineFirst', // pause mutations when offline, auto-retry on reconnect
        // Mutations are not generally idempotent. Retrying after a committed
        // response is lost can duplicate sends, tasks, events, and drafts.
        retry: false,
      },
    },
  });

const browserQueryClient = {
  queryClient: null,
  activeConnectionId: null,
} as {
  queryClient: QueryClient | null;
  activeConnectionId: string | null;
};

const getQueryClient = (connectionId: string | null) => {
  if (typeof window === 'undefined') {
    return makeQueryClient(connectionId);
  } else {
    if (!browserQueryClient.queryClient || browserQueryClient.activeConnectionId !== connectionId) {
      browserQueryClient.queryClient = makeQueryClient(connectionId);
      browserQueryClient.activeConnectionId = connectionId;
    }
    return browserQueryClient.queryClient;
  }
};

const getUrl = () => import.meta.env.VITE_PUBLIC_BACKEND_URL + '/api/trpc';

export const { TRPCProvider, useTRPC, useTRPCClient } = createTRPCContext<AppRouter>();

export const trpcClient = createTRPCClient<AppRouter>({
  links: [
    // loggerLink({ enabled: () => true }),
    httpBatchLink({
      transformer: superjson,
      url: getUrl(),
      methodOverride: 'POST',
      // `maxItems: 1` disables batching entirely. The Drafts folder renders
      // `useDraft(message.id)` per row, so on a folder with 100 drafts that
      // becomes 100 separate HTTP requests. Allow up to 10 procedures per
      // batched POST — keeps payloads small while collapsing per-row queries.
      maxItems: 10,
      fetch: (url, options) =>
        fetch(url, { ...(options as RequestInit), credentials: 'include' }).then((res) => {
          const currentPath = new URL(window.location.href).pathname;
          const redirectPath = res.headers.get('X-Zero-Redirect');
          if (!parityAuthBypass && !!redirectPath && redirectPath !== currentPath) {
            window.location.href = redirectPath;
            res.headers.delete('X-Zero-Redirect');
          }
          return res;
        }),
    }),
  ],
});

type TrpcHook = ReturnType<typeof useTRPC>;
export function QueryProvider({
  children,
  connectionId,
}: PropsWithChildren<{ connectionId: string | null }>) {
  const persister = useMemo(
    () => createIDBPersister(`zero-query-cache-${connectionId ?? 'default'}`),
    [connectionId],
  );
  const queryClient = useMemo(() => getQueryClient(connectionId), [connectionId]);

  return (
    <PersistQueryClientProvider
      client={queryClient}
      persistOptions={{
        persister,
        buster: CACHE_BURST_KEY,
        maxAge: 1000 * 60 * 60 * 24, // 24 hours
      }}
      onSuccess={() => {
        // Cap restored thread caches at 3 pages so invalidation doesn't refetch
        // 20+ pages on every reconnect. Applies to BOTH the single-account
        // `listThreads` infinite query AND the hand-rolled `listThreadsMulti`
        // infinite query — unified-view power users previously kept the full
        // N-page payload alive and paid the cost on every IDB restore.
        const trimPages = (data: InfiniteData<unknown> | undefined) => {
          if (!data) return data;
          return {
            pages: data.pages.slice(0, 3),
            pageParams: data.pageParams.slice(0, 3),
          };
        };
        queryClient.setQueriesData(
          {
            predicate: (query) => {
              const key = query.queryKey as unknown[];
              if (!Array.isArray(key) || !Array.isArray(key[0])) return false;
              const route = key[0] as unknown[];
              return (
                route[0] === 'mail' &&
                (route[1] === 'listThreads' || route[1] === 'listThreadsMulti')
              );
            },
          },
          trimPages as unknown as (
            data: InfiniteData<TrpcHook['mail']['listThreads']['~types']['output']> | undefined,
          ) => InfiniteData<TrpcHook['mail']['listThreads']['~types']['output']> | undefined,
        );
      }}
    >
      <TRPCProvider trpcClient={trpcClient} queryClient={queryClient}>
        {children}
      </TRPCProvider>
    </PersistQueryClientProvider>
  );
}

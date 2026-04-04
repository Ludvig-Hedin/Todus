import { ConnectionFilterProvider } from '@/providers/connection-filter-provider';
import { useKeyboardLayout } from '@/components/keyboard-layout-indicator';
import { LoadingProvider } from '@/components/context/loading-context';
import { NuqsAdapter } from 'nuqs/adapters/react-router/v7';
import { SidebarProvider } from '@/components/ui/sidebar';
import { useActiveConnection } from '@/hooks/use-connections';
import { PostHogProvider } from '@/lib/posthog-provider';
import { useTRPC } from '@/providers/query-provider';
import { useSettings } from '@/hooks/use-settings';
import { useQueryClient } from '@tanstack/react-query';
import { Provider as JotaiProvider } from 'jotai';
import type { PropsWithChildren } from 'react';
import { useEffect } from 'react';
import Toaster from '@/components/ui/toast';
import { ThemeProvider } from 'next-themes';

function AppWarmup() {
  const queryClient = useQueryClient();
  const trpc = useTRPC();
  const { data: activeConnection } = useActiveConnection();

  useEffect(() => {
    if (!activeConnection) return;

    const run = () => {
      const now = new Date();
      const dayStart = new Date(now);
      dayStart.setHours(0, 0, 0, 0);
      const dayEnd = new Date(now);
      dayEnd.setHours(23, 59, 59, 999);

      void queryClient.prefetchQuery(
        trpc.settings.get.queryOptions(void 0, { staleTime: Infinity }),
      );
      void queryClient.prefetchQuery(
        trpc.folders.list.queryOptions(void 0, { staleTime: 1000 * 60 * 30 }),
      );
      void queryClient.prefetchInfiniteQuery(
        trpc.mail.listThreads.infiniteQueryOptions(
          { folder: 'inbox', q: '', maxResults: 20 },
          {
            initialCursor: '',
            getNextPageParam: (lastPage) => lastPage?.nextPageToken ?? null,
            staleTime: 1000 * 60 * 5,
          },
        ),
      );
      void queryClient.prefetchQuery(
        trpc.tasks.list.queryOptions({ limit: 100 }, { staleTime: 1000 * 60 * 5 }),
      );
      void queryClient.prefetchQuery(
        trpc.calendar.events.queryOptions(
          {
            timeMin: dayStart.toISOString(),
            timeMax: dayEnd.toISOString(),
          },
          { staleTime: 1000 * 60 * 3 },
        ),
      );
    };

    const windowWithIdleCallbacks = window as Window & {
      requestIdleCallback?: (callback: IdleRequestCallback, options?: IdleRequestOptions) => number;
      cancelIdleCallback?: (handle: number) => void;
    };

    if (windowWithIdleCallbacks.requestIdleCallback) {
      const idleId = windowWithIdleCallbacks.requestIdleCallback(() => run(), { timeout: 1200 });
      return () => windowWithIdleCallbacks.cancelIdleCallback?.(idleId);
    }

    const timeoutId = window.setTimeout(run, 250);
    return () => window.clearTimeout(timeoutId);
  }, [activeConnection, queryClient, trpc]);

  return null;
}

export function ClientProviders({ children }: PropsWithChildren) {
  const { data } = useSettings();
  useKeyboardLayout();

  const theme = data?.settings.colorTheme || 'system';

  return (
    <NuqsAdapter>
      <JotaiProvider>
        <ThemeProvider
          attribute="class"
          enableSystem
          disableTransitionOnChange
          defaultTheme={theme}
        >
          <SidebarProvider>
            <PostHogProvider>
              <ConnectionFilterProvider>
                <LoadingProvider>
                  <AppWarmup />
                  {children}
                  <Toaster />
                </LoadingProvider>
              </ConnectionFilterProvider>
            </PostHogProvider>
          </SidebarProvider>
        </ThemeProvider>
      </JotaiProvider>
    </NuqsAdapter>
  );
}

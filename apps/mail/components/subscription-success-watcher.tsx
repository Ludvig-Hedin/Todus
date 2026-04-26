import { useTRPC, useTRPCClient } from '@/providers/query-provider';
import { useQueryClient } from '@tanstack/react-query';
import { useEffect } from 'react';
import { useSearchParams } from 'react-router';
import { toast } from 'sonner';

/**
 * Watches for `?success=true` (set by Stripe Checkout's success_url after a
 * Pro upgrade) and force-refreshes the cached subscription state so the user
 * immediately sees their new plan instead of waiting for the next webhook +
 * refetch cycle. Strips the query param so a refresh doesn't re-fire.
 */
export function SubscriptionSuccessWatcher() {
  const [searchParams, setSearchParams] = useSearchParams();
  const trpc = useTRPC();
  const trpcClient = useTRPCClient();
  const queryClient = useQueryClient();
  const success = searchParams.get('success');

  useEffect(() => {
    if (success !== 'true') return;
    // Strip the query param immediately so a re-render or refresh during the await
    // can't re-trigger the toast / refresh, and so we don't overwrite an unrelated
    // URL state once the async work completes.
    setSearchParams(
      (prev) => {
        const next = new URLSearchParams(prev);
        next.delete('success');
        return next;
      },
      { replace: true },
    );
    let cancelled = false;
    (async () => {
      try {
        // Force fresh read from Autumn — webhook may not have arrived yet.
        await trpcClient.subscription.refresh.mutate();
      } catch {
        // Swallow — the next render's getStatus query will catch up.
      }
      if (cancelled) return;
      await queryClient.invalidateQueries({
        queryKey: trpc.subscription.getStatus.queryKey(),
      });
      if (cancelled) return;
      toast.success("You're on Pro — welcome.", { duration: 6000 });
    })();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [success]);

  return null;
}

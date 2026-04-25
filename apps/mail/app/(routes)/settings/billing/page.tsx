import { SettingsCard } from '@/components/settings/settings-card';
import { Button } from '@/components/ui/button';
import { Progress } from '@/components/ui/progress';
import { useTRPC } from '@/providers/query-provider';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { ArrowUpRight, CreditCard, Loader2, Sparkles, X } from 'lucide-react';
import { useNavigate } from 'react-router';
import { toast } from 'sonner';

const PRO_PRODUCT_IDS = new Set(['pro_monthly', 'pro_annual']);

const formatCredits = (n: number) => (n < 1 ? n.toFixed(2) : n.toFixed(1));

const formatResetDate = (iso: string | null) => {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
};

const planLabel = (plan: string) => {
  if (plan === 'pro') return 'Pro';
  if (plan === 'enterprise') return 'Enterprise';
  if (plan === 'team') return 'Team';
  return 'Free';
};

export default function BillingSettingsPage() {
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const navigate = useNavigate();

  const statusQuery = useQuery(trpc.subscription.getStatus.queryOptions());

  const refresh = useMutation(
    trpc.subscription.refresh.mutationOptions({
      onSuccess: () => queryClient.invalidateQueries({ queryKey: trpc.subscription.getStatus.queryKey() }),
    }),
  );

  const openPortal = useMutation(
    trpc.subscription.getBillingPortalUrl.mutationOptions({
      onSuccess: ({ url }) => {
        if (url) window.location.assign(url);
        else toast.error("Couldn't open billing portal");
      },
      onError: (error) => toast.error(error.message ?? 'Failed to open billing portal'),
    }),
  );

  const cancel = useMutation(
    trpc.subscription.cancel.mutationOptions({
      onSuccess: () => {
        toast.success('Subscription canceled');
        queryClient.invalidateQueries({ queryKey: trpc.subscription.getStatus.queryKey() });
      },
      onError: (error) => toast.error(error.message ?? 'Cancellation failed'),
    }),
  );

  const status = statusQuery.data;
  const plan = status?.plan ?? 'free';
  const isPro = PRO_PRODUCT_IDS.has(plan) || plan === 'pro';
  const usage = status?.aiUsage;
  const used = usage?.used ?? 0;
  const limit = usage?.limit ?? 0;
  const remaining = usage?.remaining ?? 0;
  const pct = limit > 0 ? Math.min(100, Math.round((used / limit) * 100)) : 0;
  const resetLabel = formatResetDate(usage?.resetAt ?? null);

  return (
    <div className="space-y-8">
      <SettingsCard
        title="Plan"
        description="Your current Todus subscription."
        action={
          <Button
            variant="ghost"
            size="sm"
            disabled={refresh.isPending}
            onClick={() => refresh.mutate()}
          >
            {refresh.isPending ? (
              <Loader2 className="h-3.5 w-3.5 animate-spin" />
            ) : (
              'Refresh'
            )}
          </Button>
        }
      >
        {statusQuery.isLoading ? (
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <Loader2 className="h-4 w-4 animate-spin" /> Loading plan…
          </div>
        ) : (
          <div className="flex flex-col gap-4 rounded-lg border border-border/60 p-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <CreditCard className="h-4 w-4 text-muted-foreground" />
                <span className="text-base font-semibold">{planLabel(plan)}</span>
                {status?.status && status.status !== 'active' && (
                  <span className="rounded bg-amber-500/15 px-1.5 py-0.5 text-[11px] font-medium uppercase text-amber-600 dark:text-amber-400">
                    {status.status}
                  </span>
                )}
              </div>
              {!isPro ? (
                <Button size="sm" onClick={() => navigate('/pricing')}>
                  <Sparkles className="mr-1.5 h-3.5 w-3.5" />
                  Upgrade
                </Button>
              ) : (
                <div className="flex items-center gap-2">
                  <Button
                    size="sm"
                    variant="secondary"
                    disabled={openPortal.isPending}
                    onClick={() => openPortal.mutate({})}
                  >
                    {openPortal.isPending ? (
                      <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />
                    ) : (
                      <ArrowUpRight className="mr-1.5 h-3.5 w-3.5" />
                    )}
                    Manage billing
                  </Button>
                  <Button
                    size="sm"
                    variant="ghost"
                    className="text-destructive hover:text-destructive"
                    disabled={cancel.isPending}
                    onClick={() => {
                      if (window.confirm('Cancel your Pro subscription? You will keep access until the end of the billing period.')) {
                        cancel.mutate({ productId: plan === 'pro' ? 'pro_monthly' : plan });
                      }
                    }}
                  >
                    {cancel.isPending ? (
                      <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />
                    ) : (
                      <X className="mr-1.5 h-3.5 w-3.5" />
                    )}
                    Cancel
                  </Button>
                </div>
              )}
            </div>
          </div>
        )}
      </SettingsCard>

      <SettingsCard
        title="AI usage"
        description="Each AI message debits credits based on the model and message size. 1 credit ≈ $1 of model cost."
      >
        {statusQuery.isLoading ? (
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <Loader2 className="h-4 w-4 animate-spin" /> Loading usage…
          </div>
        ) : limit === 0 ? (
          <div className="rounded-lg border border-dashed border-border/60 p-4 text-sm text-muted-foreground">
            No AI credits on the {planLabel(plan)} plan.{' '}
            {!isPro && (
              <button
                onClick={() => navigate('/pricing')}
                className="font-medium text-foreground underline-offset-2 hover:underline"
              >
                Upgrade for credits.
              </button>
            )}
          </div>
        ) : (
          <div className="space-y-3 rounded-lg border border-border/60 p-4">
            <div className="flex items-baseline justify-between">
              <div>
                <span className="text-2xl font-semibold tabular-nums">
                  {formatCredits(used)}
                </span>
                <span className="text-sm text-muted-foreground"> / {formatCredits(limit)} credits used</span>
              </div>
              <div className="text-xs text-muted-foreground tabular-nums">
                {formatCredits(remaining)} remaining
              </div>
            </div>
            <Progress value={pct} className="h-2" />
            {resetLabel && (
              <div className="text-xs text-muted-foreground">
                Resets on {resetLabel}
              </div>
            )}
            {pct >= 80 && pct < 100 && (
              <div className="rounded border border-amber-500/40 bg-amber-500/10 p-2 text-xs text-amber-700 dark:text-amber-300">
                You've used {pct}% of your monthly AI credits.
              </div>
            )}
            {pct >= 100 && (
              <div className="rounded border border-destructive/50 bg-destructive/10 p-2 text-xs text-destructive">
                You're out of AI credits for this period. {!isPro && 'Upgrade to keep chatting.'}
              </div>
            )}
          </div>
        )}
      </SettingsCard>
    </div>
  );
}

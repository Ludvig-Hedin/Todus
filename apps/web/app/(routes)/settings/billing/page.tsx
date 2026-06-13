import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { ArrowUpRight, CreditCard, Loader2, Sparkles, X } from 'lucide-react';
import { SettingsCard } from '@/components/settings/settings-card';
import { useTRPC } from '@/providers/query-provider';
import { Progress } from '@/components/ui/progress';
import { Button } from '@/components/ui/button';
import { useNavigate } from 'react-router';
import { toast } from 'sonner';

const PLAN_INCLUDES: Record<string, string[]> = {
  free: ['1 email connection', '75 credits / month of AI chat', 'Basic AI email assistance'],
  pro: [
    'Unlimited email connections',
    '150 credits / month of AI chat & voice',
    'Auto-labeling, thread summaries, priority models',
    'Manage payment method, invoices, and cancel anytime',
  ],
};

/** Map Stripe / subscription product ids to keys used in `PLAN_INCLUDES`. */
function getPlanKey(planId: string): string {
  // Treat any `pro_*` / `team_*` / `enterprise` tier as a paid plan so a
  // paying team / enterprise customer doesn't see the Free label + Upgrade
  // button on this page. Dedicated team/enterprise copy can land later;
  // until then they get the Pro feature list which is a superset.
  if (planId === 'pro' || planId.startsWith('pro_')) return 'pro';
  if (planId === 'team' || planId.startsWith('team_') || planId === 'enterprise') return 'pro';
  if (Object.prototype.hasOwnProperty.call(PLAN_INCLUDES, planId)) return planId;
  return 'free';
}

/**
 * Credits are shown to users at 10× their internal (dollar-denominated) value
 * so plan tiers read as round, motivating numbers (Free 75, Pro 150) while
 * actual billing/limits stay unchanged. Keep this constant in sync with iOS
 * `BillingSettingsView.creditsDisplayScale` and the `PLAN_INCLUDES` copy above.
 */
const CREDITS_DISPLAY_SCALE = 10;

const formatCredits = (n: number) => {
  // Defensive: if the server ever returns NaN / Infinity (division upstream,
  // bad migration), render "0" rather than "NaN" and avoid propagating the
  // bad value into `pct` math below — which would render `NaN%` and break
  // the progress bar.
  const safe = Number.isFinite(n) && n >= 0 ? n : 0;
  const scaled = safe * CREDITS_DISPLAY_SCALE;
  if (scaled === 0) return '0';
  if (scaled < 1) return scaled.toFixed(2);
  if (scaled < 10) return scaled.toFixed(1);
  return Math.round(scaled).toString();
};

const formatUsageTotal = (n: number, unlimited: boolean) =>
  unlimited ? 'Unlimited' : formatCredits(n);

const formatResetDate = (iso: string | null) => {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
};

const planLabel = (plan: string) => {
  if (plan === 'pro') return 'Pro';
  return 'Free';
};

export default function BillingSettingsPage() {
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const navigate = useNavigate();

  const statusQuery = useQuery({
    ...trpc.subscription.getStatus.queryOptions(),
    // Cache for 30s — billing state changes rarely; webhook + success-redirect
    // already invalidate proactively, so we don't need to re-poll constantly.
    staleTime: 30 * 1000,
  });

  const refresh = useMutation(
    trpc.subscription.refresh.mutationOptions({
      onSuccess: () =>
        queryClient.invalidateQueries({ queryKey: trpc.subscription.getStatus.queryKey() }),
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

  const status = statusQuery.data;
  const plan = status?.plan ?? 'free';
  const planKey = getPlanKey(plan);
  const isPro = planKey === 'pro';
  const usage = status?.aiUsage;
  const used = usage?.used ?? 0;
  const limit = usage?.limit ?? 0;
  const unlimited = usage?.unlimited ?? false;
  // Use `Math.ceil` so any non-zero usage drops the headline below 100% —
  // `Math.round` would report "100% remaining" for 0.4% consumption while
  // the "Used X of Y credits" subtitle simultaneously shows real usage.
  // Mirrors iOS `BillingSettingsView.percentRemaining`.
  const pct = !unlimited && limit > 0 ? Math.min(100, Math.ceil((used / limit) * 100)) : 0;
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
            {refresh.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : 'Refresh'}
          </Button>
        }
      >
        {statusQuery.isLoading ? (
          <div className="text-muted-foreground flex items-center gap-2 text-sm">
            <Loader2 className="h-4 w-4 animate-spin" /> Loading plan…
          </div>
        ) : (
          <div className="border-border/60 flex flex-col gap-4 rounded-lg border p-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <CreditCard className="text-muted-foreground h-4 w-4" />
                <span className="text-base font-semibold">{planLabel(planKey)}</span>
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
                    disabled={openPortal.isPending}
                    onClick={() => openPortal.mutate({})}
                  >
                    {openPortal.isPending ? (
                      <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />
                    ) : (
                      <X className="mr-1.5 h-3.5 w-3.5" />
                    )}
                    Cancel in portal
                  </Button>
                </div>
              )}
            </div>
            {(PLAN_INCLUDES[planKey] ?? PLAN_INCLUDES.free) && (
              <div className="border-border/60 mt-1 border-t pt-3">
                <div className="text-muted-foreground mb-1.5 text-[11px] font-medium uppercase tracking-wide">
                  Includes
                </div>
                <ul className="space-y-1">
                  {(PLAN_INCLUDES[planKey] ?? PLAN_INCLUDES.free).map((item) => (
                    <li key={item} className="text-foreground/80 flex items-start gap-2 text-sm">
                      <span className="mt-1.5 inline-block h-1 w-1 shrink-0 rounded-full bg-current opacity-60" />
                      <span>{item}</span>
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </div>
        )}
      </SettingsCard>

      <SettingsCard
        title="AI usage"
        description="Every AI chat and voice session uses credits based on the model and length."
        action={
          resetLabel ? (
            <span className="text-muted-foreground text-xs">Resets {resetLabel}</span>
          ) : null
        }
      >
        {statusQuery.isLoading ? (
          <div className="text-muted-foreground flex items-center gap-2 text-sm">
            <Loader2 className="h-4 w-4 animate-spin" /> Loading usage…
          </div>
        ) : (
          <div className="border-border/60 bg-muted/30 space-y-5 rounded-xl border p-6">
            {/* Big number — credits remaining */}
            <div className="flex flex-col items-center gap-1 text-center">
              <div className="flex items-baseline gap-2 tabular-nums">
                <span className="text-5xl font-semibold leading-none">
                  {unlimited ? 'Unlimited' : limit > 0 ? `${Math.max(0, 100 - pct)}%` : '0'}
                </span>
                <span className="text-muted-foreground text-base">
                  {unlimited ? 'AI credits' : limit > 0 ? 'remaining' : 'credits'}
                </span>
              </div>
              <div className="text-muted-foreground text-xs">
                {unlimited
                  ? 'Unlimited AI usage on this plan.'
                  : limit > 0
                    ? `Used ${formatCredits(used)} of ${formatCredits(limit)} credits`
                    : 'No credits available on this plan.'}
              </div>
            </div>

            {/* Big progress bar */}
            <Progress value={pct} className="h-3" />

            {/* Used + warnings */}
            <div className="text-muted-foreground flex items-center justify-between text-xs tabular-nums">
              <span>Used: {formatCredits(used)}</span>
              <span>Total: {formatUsageTotal(limit, unlimited)}</span>
            </div>

            {!unlimited && pct >= 80 && pct < 100 && (
              <div className="rounded border border-amber-500/40 bg-amber-500/10 p-2.5 text-sm text-amber-700 dark:text-amber-300">
                You've used {pct}% of your AI credits this period.
              </div>
            )}
            {!unlimited && pct >= 100 && (
              <div className="border-destructive/50 bg-destructive/10 text-destructive flex items-center justify-between gap-3 rounded border p-2.5 text-sm">
                <span>You're out of AI credits for this period.</span>
                {!isPro && (
                  <Button size="sm" onClick={() => navigate('/pricing')}>
                    Upgrade
                  </Button>
                )}
              </div>
            )}
          </div>
        )}
      </SettingsCard>
    </div>
  );
}

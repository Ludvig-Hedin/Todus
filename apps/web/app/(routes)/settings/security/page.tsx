'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useTRPC } from '@/providers/query-provider';
import { SettingsCard } from '@/components/settings/settings-card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { TwoFactorCard } from '@/components/settings/two-factor-card';
import { Monitor, Smartphone, Tablet, Globe, Clock, LogOut, ShieldCheck } from 'lucide-react';
import { m } from '@/paraglide/messages';
import { format, isValid } from 'date-fns';
import { toast } from 'sonner';

function deviceIcon(device: string) {
  const d = device.toLowerCase();
  if (d.includes('ipad') || d.includes('tablet')) return <Tablet className="h-4 w-4" />;
  if (d.includes('iphone') || d.includes('ios') || d.includes('android') || d.includes('mobile'))
    return <Smartphone className="h-4 w-4" />;
  return <Monitor className="h-4 w-4" />;
}

export default function SecurityPage() {
  const trpc = useTRPC();
  const queryClient = useQueryClient();

  const {
    data,
    isLoading,
    isError,
    error,
    refetch,
  } = useQuery(trpc.sessions.list.queryOptions());

  const sessions = data?.sessions ?? [];

  const revokeMutation = useMutation(
    trpc.sessions.revoke.mutationOptions({
      onSuccess: (result) => {
        queryClient.invalidateQueries({ queryKey: trpc.sessions.list.queryKey() });
        if (result.revokedCurrent) {
          toast.success('Signed out of this session.');
        } else {
          toast.success('Device signed out.');
        }
      },
      onError: () => toast.error('Failed to sign out device. Please try again.'),
    }),
  );

  const revokeAllMutation = useMutation(
    trpc.sessions.revokeAll.mutationOptions({
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: trpc.sessions.list.queryKey() });
        toast.success('Signed out of all other devices.');
      },
      onError: () => toast.error('Failed to sign out other devices. Please try again.'),
    }),
  );

  const otherSessions = sessions.filter((s) => !s.isCurrent);

  return (
    <div className="grid gap-5">
      <TwoFactorCard />

      <SettingsCard
        title={m['pages.settings.security.title']()}
        description={m['pages.settings.security.description']()}
      >
        {isLoading ? (
          <div className="divide-y">
            {[...Array(2)].map((_, i) => (
              <div key={i} className="flex items-start gap-3 px-4 py-3">
                <Skeleton className="mt-0.5 h-8 w-8 rounded-full" />
                <div className="flex-1 space-y-1.5">
                  <Skeleton className="h-4 w-40" />
                  <Skeleton className="h-3 w-56" />
                </div>
              </div>
            ))}
          </div>
        ) : isError ? (
          <div className="flex flex-col items-center justify-center py-8 text-center">
            <div className="bg-destructive/10 mb-4 flex h-12 w-12 items-center justify-center rounded-full">
              <ShieldCheck className="text-destructive h-6 w-6" />
            </div>
            <h3 className="text-base font-semibold">Couldn't load sessions</h3>
            <p className="text-muted-foreground mt-1.5 max-w-sm text-[13px]">
              {error instanceof Error ? error.message : 'An unexpected error occurred.'}
            </p>
            <Button variant="outline" size="sm" className="mt-4" onClick={() => refetch()}>
              Try again
            </Button>
          </div>
        ) : sessions.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-8 text-center">
            <div className="bg-muted mb-4 flex h-12 w-12 items-center justify-center rounded-full">
              <ShieldCheck className="text-muted-foreground h-6 w-6" />
            </div>
            <h3 className="text-base font-semibold">No active sessions</h3>
            <p className="text-muted-foreground mt-1.5 max-w-sm text-[13px]">
              New sign-ins will appear here automatically.
            </p>
          </div>
        ) : (
          <div className="divide-y">
            {sessions.map((session) => (
              <div key={session.id} className="flex items-center gap-3 px-4 py-3">
                <div className="bg-muted flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-full">
                  {deviceIcon(session.device)}
                </div>

                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-medium">{session.device}</span>
                    {session.isCurrent && (
                      <Badge variant="secondary" className="text-[11px]">
                        This device
                      </Badge>
                    )}
                  </div>
                  <div className="text-muted-foreground mt-0.5 flex flex-wrap items-center gap-x-3 gap-y-0.5 text-[12px]">
                    {session.location && session.location !== 'Unavailable' && (
                      <span className="flex items-center gap-1">
                        <Globe className="h-3 w-3" />
                        {session.location}
                      </span>
                    )}
                    {(() => {
                      const updatedAt = session.updatedAt ? new Date(session.updatedAt) : null;
                      const valid = updatedAt && isValid(updatedAt);
                      return (
                        <span className="flex items-center gap-1">
                          <Clock className="h-3 w-3" />
                          {valid
                            ? `Last active ${format(updatedAt, 'MMM d, yyyy · h:mm a')}`
                            : 'Last active unknown'}
                        </span>
                      );
                    })()}
                  </div>
                </div>

                {!session.isCurrent && (
                  <Button
                    variant="ghost"
                    size="sm"
                    className="text-destructive hover:text-destructive flex-shrink-0 gap-1.5"
                    disabled={revokeMutation.isPending}
                    onClick={() => revokeMutation.mutate({ sessionId: session.id })}
                  >
                    <LogOut className="h-3.5 w-3.5" />
                    Sign out
                  </Button>
                )}
              </div>
            ))}

            {otherSessions.length > 0 && (
              <div className="px-4 py-3">
                <Button
                  variant="outline"
                  size="sm"
                  className="text-destructive border-destructive/30 hover:bg-destructive/5 gap-1.5"
                  disabled={revokeAllMutation.isPending}
                  onClick={() => revokeAllMutation.mutate()}
                >
                  <LogOut className="h-3.5 w-3.5" />
                  {revokeAllMutation.isPending ? 'Signing out…' : 'Sign out all other devices'}
                </Button>
              </div>
            )}
          </div>
        )}
      </SettingsCard>
    </div>
  );
}

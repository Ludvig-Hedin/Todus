import { SettingsCard } from '@/components/settings/settings-card';
import { Button } from '@/components/ui/button';
import { useSession, signOut } from '@/lib/auth-client';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useTRPC } from '@/providers/query-provider';
import { m } from '@/paraglide/messages';
import { format } from 'date-fns';
import { ShieldCheck } from 'lucide-react';
import { toast } from 'sonner';

function formatTimestamp(value: Date | string) {
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? '—' : format(date, 'PPp');
}

export default function SecurityPage() {
  const { data: session } = useSession();
  const trpc = useTRPC();
  const queryClient = useQueryClient();
  const currentSessionId = (session as { session?: { id?: string } } | null)?.session?.id ?? null;

  const sessionsQuery = useQuery(
    trpc.sessions.list.queryOptions(undefined, {
      enabled: !!session?.user?.id,
      refetchOnWindowFocus: true,
      refetchInterval: 15_000,
    }),
  );

  const { mutateAsync: revokeSession, isPending: isRevokingSession } = useMutation(
    trpc.sessions.revoke.mutationOptions({
      onSuccess: async () => {
        await queryClient.invalidateQueries({ queryKey: trpc.sessions.list.queryKey() });
      },
    }),
  );

  const { mutateAsync: revokeAllSessions, isPending: isRevokingAll } = useMutation(
    trpc.sessions.revokeAll.mutationOptions({
      onSuccess: async () => {
        await queryClient.invalidateQueries({ queryKey: trpc.sessions.list.queryKey() });
      },
    }),
  );

  async function handleRevoke(sessionId: string) {
    try {
      const result = await revokeSession({ sessionId });
      toast.success('Session logged out.');

      if (result.revokedCurrent || sessionId === currentSessionId) {
        signOut({
          fetchOptions: {
            onSuccess: () => {
              window.location.href = '/login';
            },
          },
        });
      }
    } catch (error) {
      console.error(error);
      toast.error('Failed to log out that session.');
    }
  }

  async function handleRevokeAll() {
    try {
      const result = await revokeAllSessions();
      toast.success(
        result.revokedCount > 0 ? `Logged out ${result.revokedCount} session(s).` : 'No sessions to log out.',
      );

      if (result.revokedCurrent) {
        signOut({
          fetchOptions: {
            onSuccess: () => {
              window.location.href = '/login';
            },
          },
        });
      }
    } catch (error) {
      console.error(error);
      toast.error('Failed to log out all devices.');
    }
  }

  const sessions = sessionsQuery.data?.sessions ?? [];

  return (
    <div className="grid gap-6">
      <SettingsCard
        title={m['pages.settings.security.title']()}
        description="Review every signed-in device and revoke access without changing your password."
        action={
          <Button
            variant="destructive"
            size="sm"
            onClick={handleRevokeAll}
            isLoading={isRevokingAll}
            disabled={sessions.length === 0 || isRevokingAll}
          >
            Log out all devices
          </Button>
        }
      >
        <div className="overflow-hidden rounded-2xl border border-border/70">
          <div className="grid grid-cols-[1.4fr_1fr_1fr_1fr_0.7fr] gap-4 border-b border-border/70 bg-muted/30 px-4 py-3 text-[11px] font-medium uppercase tracking-[0.14em] text-muted-foreground">
            <span>Device</span>
            <span>Location</span>
            <span>Created</span>
            <span>Updated</span>
            <span>Action</span>
          </div>

          {sessionsQuery.isLoading ? (
            <div className="px-4 py-10 text-sm text-muted-foreground">Loading active sessions…</div>
          ) : sessionsQuery.isError ? (
            <div className="px-4 py-10 text-sm text-destructive">
              Failed to load active sessions.
            </div>
          ) : sessions.length === 0 ? (
            <div className="flex flex-col items-center justify-center px-4 py-10 text-center">
              <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-muted">
                <ShieldCheck className="h-6 w-6 text-muted-foreground" />
              </div>
              <h3 className="text-base font-semibold">No active sessions found</h3>
              <p className="mt-1.5 max-w-sm text-[13px] text-muted-foreground">
                New sign-ins will appear here automatically so you can review and revoke them.
              </p>
            </div>
          ) : (
            <div className="divide-y divide-border/60">
              {sessions.map((activeSession) => (
                <div
                  key={activeSession.id}
                  className="grid grid-cols-[1.4fr_1fr_1fr_1fr_0.7fr] gap-4 px-4 py-3 text-sm"
                >
                  <div className="min-w-0">
                    <div className="truncate font-medium text-foreground">
                      {activeSession.device}
                    </div>
                    {activeSession.id === currentSessionId || activeSession.isCurrent ? (
                      <div className="mt-1 text-xs text-muted-foreground">Current device</div>
                    ) : null}
                  </div>
                  <div className="text-muted-foreground">{activeSession.location}</div>
                  <div className="text-muted-foreground">{formatTimestamp(activeSession.createdAt)}</div>
                  <div className="text-muted-foreground">{formatTimestamp(activeSession.updatedAt)}</div>
                  <div>
                    <Button
                      variant="ghost"
                      size="sm"
                      className="h-8 px-2 text-destructive hover:text-destructive"
                      onClick={() => handleRevoke(activeSession.id)}
                      disabled={isRevokingSession || isRevokingAll}
                    >
                      Log out
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </SettingsCard>
    </div>
  );
}

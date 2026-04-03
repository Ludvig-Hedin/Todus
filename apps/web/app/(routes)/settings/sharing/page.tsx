'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useTRPC } from '@/providers/query-provider';
import { SettingsCard } from '@/components/settings/settings-card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Share2, Link, Trash2, Clock } from 'lucide-react';
import { toast } from 'sonner';
import { format } from 'date-fns';

export default function SharingSettingsPage() {
  const trpc = useTRPC();
  const queryClient = useQueryClient();

  const { data: shares = [], isLoading } = useQuery(trpc.sharing.listMine.queryOptions());

  const revokeMutation = useMutation(
    trpc.sharing.revoke.mutationOptions({
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: trpc.sharing.listMine.queryKey() });
        toast.success('Link revoked.');
      },
      onError: () => toast.error('Failed to revoke link.'),
    }),
  );

  return (
    <div className="grid gap-6">
      <SettingsCard
        title="Shared conversations"
        description="Read-only links you've created to share AI conversations."
      >
        {isLoading ? (
          <div className="py-8 text-center">
            <p className="text-muted-foreground text-sm">Loading…</p>
          </div>
        ) : shares.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-8 text-center">
            <div className="bg-muted mb-4 flex h-12 w-12 items-center justify-center rounded-full">
              <Share2 className="text-muted-foreground h-6 w-6" />
            </div>
            <h3 className="text-base font-semibold">No shared links yet</h3>
            <p className="text-muted-foreground mt-1.5 max-w-sm text-[13px]">
              Create share links from any AI conversation using the Share button.
            </p>
          </div>
        ) : (
          <div className="divide-y">
            {shares.map((share) => {
              const shareUrl = `${window.location.origin}/share/${share.slug}`;
              return (
                <div key={share.id} className="flex items-start justify-between gap-4 py-4">
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <p className="truncate text-sm font-medium">
                        {share.title || 'Untitled'}
                      </p>
                      <StatusBadge status={share.status} />
                      {share.passwordProtected && (
                        <Badge variant="outline" className="text-xs">
                          Protected
                        </Badge>
                      )}
                    </div>
                    <div className="text-muted-foreground mt-1 flex items-center gap-3 text-xs">
                      <span className="flex items-center gap-1">
                        <Link className="h-3 w-3" />
                        <span className="max-w-[200px] truncate font-mono">{share.slug}</span>
                      </span>
                      <span className="flex items-center gap-1">
                        <Clock className="h-3 w-3" />
                        Created {format(new Date(share.createdAt), 'MMM d, yyyy')}
                      </span>
                      {share.expiresAt && (
                        <span>
                          Expires {format(new Date(share.expiresAt), 'MMM d, yyyy')}
                        </span>
                      )}
                    </div>
                  </div>

                  <div className="flex shrink-0 items-center gap-2">
                    {share.status === 'active' && (
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={async () => {
                          try {
                            await navigator.clipboard.writeText(shareUrl);
                            toast.success('Link copied!');
                          } catch {
                            toast.error('Failed to copy link.');
                          }
                        }}
                      >
                        Copy link
                      </Button>
                    )}
                    {share.status !== 'revoked' && (
                      <Button
                        variant="ghost"
                        size="sm"
                        className="text-destructive hover:text-destructive"
                        onClick={() => revokeMutation.mutate({ id: share.id })}
                        disabled={revokeMutation.isPending}
                      >
                        <Trash2 className="h-4 w-4" />
                        <span className="sr-only">Revoke</span>
                      </Button>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </SettingsCard>
    </div>
  );
}

function StatusBadge({ status }: { status: string }) {
  if (status === 'active') {
    return (
      <Badge className="bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400 text-xs">
        Active
      </Badge>
    );
  }
  if (status === 'expired') {
    return <Badge variant="secondary" className="text-xs">Expired</Badge>;
  }
  if (status === 'revoked') {
    return <Badge variant="destructive" className="text-xs">Revoked</Badge>;
  }
  if (status === 'pending') {
    return <Badge variant="secondary" className="text-xs">Pending</Badge>;
  }
  if (status === 'draft') {
    return <Badge variant="secondary" className="text-xs">Draft</Badge>;
  }
  const label = status.trim() ? `${status.charAt(0).toUpperCase()}${status.slice(1)}` : 'Unknown';
  return <Badge variant="secondary" className="text-xs">{label}</Badge>;
}

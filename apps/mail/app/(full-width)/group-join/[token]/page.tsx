import { useParams, useNavigate } from 'react-router';
import { useQuery, useMutation } from '@tanstack/react-query';
import { useTRPC } from '@/providers/query-provider';
import { useSession } from '@/lib/auth-client';
import { Button } from '@/components/ui/button';
import { Users } from 'lucide-react';

export default function GroupJoinPage() {
  const { token } = useParams<{ token: string }>();
  const navigate = useNavigate();
  const trpc = useTRPC();
  const { data: session } = useSession();

  const { data: groupInfo, isLoading, error } = useQuery(
    trpc.groups.getByInvite.queryOptions(
      { token: token! },
      { enabled: !!token && !!session?.user, retry: false },
    ),
  );

  const joinMutation = useMutation(
    trpc.groups.join.mutationOptions({
      onSuccess: (result) => {
        // Navigate into the group chat view
        navigate(`/mail?groupId=${result.groupId}`);
      },
      onError: (err) => {
        console.error('Failed to join group:', err);
      },
    }),
  );

  if (!session?.user) {
    return (
      <div className="flex h-screen flex-col items-center justify-center gap-4 px-4 text-center">
        <p className="text-xl font-semibold">Sign in to join</p>
        <p className="text-muted-foreground max-w-sm text-sm">
          You need an account to join this group chat.
        </p>
        <Button onClick={() => navigate(`/login?redirect=/g/${token}`)}>Sign in</Button>
      </div>
    );
  }

  if (isLoading) {
    return (
      <div className="flex h-screen items-center justify-center">
        <p className="text-muted-foreground text-sm">Loading…</p>
      </div>
    );
  }

  if (error || !groupInfo) {
    return (
      <div className="flex h-screen flex-col items-center justify-center gap-3 px-4 text-center">
        <p className="text-xl font-semibold">Invite not found</p>
        <p className="text-muted-foreground max-w-sm text-sm">
          This invite link may have been revoked or is invalid.
        </p>
        <Button variant="outline" onClick={() => navigate('/')}>
          Go home
        </Button>
      </div>
    );
  }

  return (
    <div className="flex h-screen flex-col items-center justify-center px-4">
      <div className="flex w-full max-w-sm flex-col items-center gap-6 text-center">
        <div className="bg-muted flex h-16 w-16 items-center justify-center rounded-2xl">
          <Users className="text-muted-foreground h-8 w-8" />
        </div>

        <div>
          <h1 className="text-2xl font-semibold">{groupInfo.name}</h1>
          <p className="text-muted-foreground mt-1 text-sm">
            {groupInfo.memberCount} {groupInfo.memberCount === 1 ? 'member' : 'members'}
          </p>
        </div>

        {groupInfo.alreadyMember ? (
          <div className="flex flex-col gap-3 w-full">
            <p className="text-muted-foreground text-sm">You're already a member.</p>
            <Button onClick={() => navigate(`/mail?groupId=${groupInfo.id}`)}>
              Open group chat
            </Button>
          </div>
        ) : (
          <>
            <Button
              className="w-full"
              onClick={() => joinMutation.mutate({ token: token! })}
              disabled={joinMutation.isPending}
            >
              {joinMutation.isPending ? 'Joining…' : 'Join group'}
            </Button>
            {joinMutation.isError && (
              <p className="text-destructive text-sm">
                {joinMutation.error?.message ?? 'Failed to join group. Please try again.'}
              </p>
            )}
          </>
        )}
      </div>
    </div>
  );
}

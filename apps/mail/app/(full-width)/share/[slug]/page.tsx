import { useState } from 'react';
import { useParams, useNavigate } from 'react-router';
import { useQuery, useMutation } from '@tanstack/react-query';
import { useTRPC } from '@/providers/query-provider';
import { useSession } from '@/lib/auth-client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { cn } from '@/lib/utils';

export default function SharedConversationPage() {
  const { slug } = useParams<{ slug: string }>();
  const navigate = useNavigate();
  const trpc = useTRPC();
  const { data: session } = useSession();

  const [passwordInput, setPasswordInput] = useState('');
  // The submitted password — only set when the user clicks "Unlock"
  const [submittedPassword, setSubmittedPassword] = useState<string | undefined>(undefined);
  const [passwordError, setPasswordError] = useState(false);

  const { data, error, isLoading } = useQuery(
    trpc.sharing.get.queryOptions(
      { slug: slug!, password: submittedPassword },
      {
        retry: false,
        // Re-fetch when submittedPassword changes (user entered a password)
        enabled: !!slug,
      },
    ),
  );

  const importMutation = useMutation(
    trpc.sharing.import.mutationOptions({
      onSuccess: (result) => {
        // Navigate to the newly created conversation in the AI sidebar
        navigate(`/mail?conversationId=${result.newConversationId}`);
      },
      onError: (err) => {
        console.error('Failed to import conversation:', err);
      },
    }),
  );

  const handleUnlock = () => {
    setPasswordError(false);
    setSubmittedPassword(passwordInput);
  };

  // Show password error when wrong password was submitted
  const hasWrongPassword =
    error?.message?.toLowerCase().includes('incorrect password') ||
    (submittedPassword !== undefined && error?.data?.code === 'UNAUTHORIZED');

  if (isLoading) {
    return (
      <div className="flex h-screen items-center justify-center">
        <div className="text-muted-foreground text-sm">Loading…</div>
      </div>
    );
  }

  // Expired, revoked, or not found
  if (error && !hasWrongPassword) {
    return (
      <div className="flex h-screen flex-col items-center justify-center gap-3 px-4 text-center">
        <p className="text-xl font-semibold">Not available</p>
        <p className="text-muted-foreground max-w-sm text-sm">
          {error.message || 'This shared conversation is not available.'}
        </p>
        <Button variant="outline" onClick={() => navigate('/')}>
          Go home
        </Button>
      </div>
    );
  }

  // Password gate
  if (data?.passwordRequired || hasWrongPassword) {
    return (
      <div className="flex h-screen flex-col items-center justify-center px-4">
        <div className="flex w-full max-w-sm flex-col gap-4">
          <div className="text-center">
            <h1 className="text-xl font-semibold">Password required</h1>
            <p className="text-muted-foreground mt-1 text-sm">
              This conversation is protected.
            </p>
          </div>
          <Input
            type="password"
            placeholder="Enter password"
            value={passwordInput}
            onChange={(e) => setPasswordInput(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && handleUnlock()}
            className={cn(hasWrongPassword && 'border-destructive')}
          />
          {hasWrongPassword && (
            <p className="text-destructive -mt-2 text-sm">Incorrect password. Try again.</p>
          )}
          <Button onClick={handleUnlock} disabled={!passwordInput}>
            Unlock
          </Button>
        </div>
      </div>
    );
  }

  if (!data || data.passwordRequired) return null;

  const messages = data.messages as Array<{ role: string; content: string }>;

  return (
    <div className="mx-auto max-w-2xl px-4 py-10">
      {/* Header */}
      <div className="mb-8">
        <h1 className="text-2xl font-semibold">{data.title || 'Shared conversation'}</h1>
        {data.createdAt && (
          <p className="text-muted-foreground mt-1 text-sm">
            Shared {new Date(data.createdAt).toLocaleDateString()}
          </p>
        )}
      </div>

      {/* Message bubbles — read-only snapshot */}
      <div className="flex flex-col gap-4">
        {messages.map((msg, i) => (
          <div
            key={i}
            className={cn('flex', msg.role === 'user' ? 'justify-end' : 'justify-start')}
          >
            <div
              className={cn(
                'max-w-[80%] rounded-2xl px-4 py-2.5 text-sm',
                msg.role === 'user'
                  ? 'bg-primary text-primary-foreground'
                  : 'bg-muted text-foreground',
              )}
            >
              <p className="whitespace-pre-wrap">{msg.content}</p>
            </div>
          </div>
        ))}
      </div>

      {/* Import CTA — only visible when user is logged in */}
      {session?.user && (
        <div className="mt-10 flex justify-center">
          <div className="flex flex-col items-center gap-2">
            <Button
              variant="outline"
              onClick={() =>
                importMutation.mutate({
                  slug: slug!,
                  password: submittedPassword,
                })
              }
              disabled={importMutation.isPending}
            >
              {importMutation.isPending ? 'Copying…' : 'Use this conversation as template'}
            </Button>
            {importMutation.isError && (
              <p className="text-destructive text-sm">
                {importMutation.error?.message ?? 'Failed to import conversation.'}
              </p>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

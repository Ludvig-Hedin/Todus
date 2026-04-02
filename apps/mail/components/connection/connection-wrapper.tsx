import { useConnections } from '@/hooks/use-connections';
import { useLocation, useNavigate } from 'react-router';
import { useEffect, useMemo, useState } from 'react';
import { emailProviders } from '@/lib/constants';
import { authClient } from '@/lib/auth-client';
import { Button } from '../ui/button';
import { X } from 'lucide-react';
import { toast } from 'sonner';

const DISMISS_KEY = 'dismissedConnectionPrompt';

export const ConnectionWrapper = () => {
  const { data: connectionsData, isLoading } = useConnections();
  const location = useLocation();
  const navigate = useNavigate();
  const [dismissed, setDismissed] = useState(false);

  const hasNoConnections = (connectionsData?.connections.length ?? 0) === 0;

  useEffect(() => {
    if (typeof window === 'undefined') return;
    try {
      setDismissed(localStorage.getItem(DISMISS_KEY) === 'true');
    } catch (error) {
      console.warn('Failed to read dismissed connection prompt state:', error);
      setDismissed(false);
    }
  }, []);

  useEffect(() => {
    if (typeof window === 'undefined') return;

    if (!hasNoConnections) {
      try {
        localStorage.removeItem(DISMISS_KEY);
      } catch (error) {
        console.warn('Failed to clear dismissed connection prompt state:', error);
      }
      setDismissed(false);
    }
  }, [hasNoConnections]);

  const providerButtons = useMemo(
    () =>
      emailProviders.map((provider) => {
        const Icon = provider.icon;

        return (
          <Button
            key={provider.name}
            variant="outline"
            className="h-11 justify-start gap-3 rounded-xl border shadow-none"
            onClick={async () => {
              const callbackURL = `${window.location.origin}${location.pathname}`;
              try {
                await authClient.linkSocial({
                  provider: provider.providerId,
                  callbackURL,
                });
              } catch (error) {
                console.error('Failed to link social provider:', {
                  provider: provider.providerId,
                  callbackURL,
                  error,
                });
                toast.error(`Could not connect ${provider.name}.`);
              }
            }}
          >
            <Icon className="size-5!" />
            <span>{provider.name}</span>
          </Button>
        );
      }),
    [location.pathname],
  );

  if (isLoading || !hasNoConnections || dismissed) return null;

  return (
    <div className="pointer-events-none fixed inset-x-4 bottom-4 z-40 md:inset-x-auto md:bottom-auto md:right-4 md:top-4 md:w-[360px]">
      <div className="bg-background/98 pointer-events-auto rounded-2xl border p-4 shadow-2xl backdrop-blur">
        <div className="flex items-start justify-between gap-3">
          <div className="space-y-1">
            <p className="text-foreground text-sm font-semibold">Connect an inbox to start</p>
            <p className="text-muted-foreground text-sm leading-relaxed">
              Add Gmail or Outlook to load messages, use AI on your mail, and start replying from
              this workspace.
            </p>
          </div>
          <Button
            variant="ghost"
            size="icon"
            className="h-8 w-8 shrink-0 rounded-full"
            onClick={() => {
              localStorage.setItem(DISMISS_KEY, 'true');
              setDismissed(true);
            }}
          >
            <X className="h-4 w-4" />
            <span className="sr-only">Dismiss connection prompt</span>
          </Button>
        </div>

        <div className="mt-4 grid gap-2">{providerButtons}</div>

        <div className="mt-4 flex flex-wrap gap-2">
          <Button
            variant="secondary"
            className="rounded-full"
            onClick={() => navigate('/settings/connections')}
          >
            Open connection settings
          </Button>
          <Button
            variant="ghost"
            className="text-muted-foreground rounded-full"
            onClick={() => {
              localStorage.setItem(DISMISS_KEY, 'true');
              setDismissed(true);
            }}
          >
            Continue without email
          </Button>
        </div>
      </div>
    </div>
  );
};

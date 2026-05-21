import { useConnections } from '@/hooks/use-connections';
import { useLocation, useNavigate } from 'react-router';
import { useEffect, useMemo, useState } from 'react';
import { emailProviders } from '@/lib/constants';
import { authClient, useSession } from '@/lib/auth-client';
import { Button } from '../ui/button';
import { X } from 'lucide-react';
import { toast } from 'sonner';

// Session-scoped: dismissing hides the prompt for the current tab/session
// only, so users without a connected inbox are reminded again next time they
// open the app rather than silently losing the connection-flow entry point.
const DISMISS_KEY = 'dismissedConnectionPrompt';
// Onboarding completion is stored per-user as `hasCompletedOnboarding:${uid}`
// (see components/onboarding.tsx). Older builds wrote the base key only, so
// we fall back to it for already-onboarded users.
const ONBOARDING_KEY_BASE = 'hasCompletedOnboarding';
const onboardingKeyForUser = (userId: string | undefined) =>
  userId ? `${ONBOARDING_KEY_BASE}:${userId}` : ONBOARDING_KEY_BASE;

export const ConnectionWrapper = () => {
  const { data: connectionsData, isLoading, isError } = useConnections();
  const location = useLocation();
  const navigate = useNavigate();
  const { data: session } = useSession();
  const userId = (session?.user?.id as string | undefined) ?? undefined;
  const ONBOARDING_KEY = onboardingKeyForUser(userId);
  const [dismissed, setDismissed] = useState(false);
  // Hide connection prompt while the onboarding tour is still in progress so
  // the two surfaces don't stack on top of each other on first run.
  const [onboardingDone, setOnboardingDone] = useState(true);

  // On `connections.list` error, `data` stays undefined → don't surface the
  // "Connect an inbox" prompt over a user who actually has connections.
  const hasNoConnections = !isError && (connectionsData?.connections.length ?? 0) === 0;

  useEffect(() => {
    if (typeof window === 'undefined') return;
    try {
      // Migrate any leftover localStorage dismiss flag — previous behavior
      // persisted dismissal forever, which trapped users in an empty inbox.
      if (localStorage.getItem(DISMISS_KEY) === 'true') {
        localStorage.removeItem(DISMISS_KEY);
      }
      setDismissed(sessionStorage.getItem(DISMISS_KEY) === 'true');
      // Read user-scoped key first; fall back to base key for users onboarded
      // on a previous build (so they don't see the tour again).
      const doneScoped = localStorage.getItem(ONBOARDING_KEY) === 'true';
      const doneBase = localStorage.getItem(ONBOARDING_KEY_BASE) === 'true';
      setOnboardingDone(doneScoped || doneBase);
    } catch (error) {
      console.warn('Failed to read dismissed connection prompt state:', error);
      setDismissed(false);
      setOnboardingDone(true);
    }
    // Re-check onboarding completion when storage changes (other tab finishes tour).
    const onStorage = (e: StorageEvent) => {
      if (e.key === ONBOARDING_KEY || e.key === ONBOARDING_KEY_BASE) {
        setOnboardingDone(e.newValue === 'true');
      }
    };
    // Same-tab signal fired by OnboardingWrapper on close — storage events
    // don't fire in the same tab that wrote the value.
    const onCompleted = () => setOnboardingDone(true);
    window.addEventListener('storage', onStorage);
    window.addEventListener('onboarding-completed', onCompleted);
    return () => {
      window.removeEventListener('storage', onStorage);
      window.removeEventListener('onboarding-completed', onCompleted);
    };
  }, [ONBOARDING_KEY]);

  useEffect(() => {
    if (typeof window === 'undefined') return;

    if (!hasNoConnections) {
      try {
        sessionStorage.removeItem(DISMISS_KEY);
      } catch (error) {
        console.warn('Failed to clear dismissed connection prompt state:', error);
      }
      setDismissed(false);
    }
  }, [hasNoConnections]);

  const handleDismiss = () => {
    try {
      sessionStorage.setItem(DISMISS_KEY, 'true');
    } catch (error) {
      console.warn('Failed to persist dismissed connection prompt state:', error);
    }
    setDismissed(true);
  };

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

  if (isLoading || isError || !hasNoConnections || dismissed || !onboardingDone) return null;

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
            onClick={handleDismiss}
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
            onClick={handleDismiss}
          >
            Continue without email
          </Button>
        </div>
      </div>
    </div>
  );
};

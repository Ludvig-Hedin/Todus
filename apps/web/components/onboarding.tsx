import { Dialog, DialogContent, DialogTitle } from '@/components/ui/dialog';
import { useConnections } from '@/hooks/use-connections';
import { Button } from '@/components/ui/button';
import { useSession } from '@/lib/auth-client';
import { useState, useEffect } from 'react';
import { APP_NAME } from '@/lib/branding';
import confetti from 'canvas-confetti';

// Storage key for tracking onboarding completion. Scoped per-user so signing
// out and signing in as a different account doesn't skip the tour.
const ONBOARDING_KEY_BASE = 'hasCompletedOnboarding';
const onboardingKeyForUser = (userId: string | undefined) =>
  userId ? `${ONBOARDING_KEY_BASE}:${userId}` : ONBOARDING_KEY_BASE;

const steps = [
  {
    title: `Welcome to ${APP_NAME}`,
    description:
      'Process inbox work faster with clearer threads, quicker replies, and built-in AI help.',
    media: { src: '/onboarding/get-started.png', type: 'image' as const },
  },
  {
    title: 'Find the next thing to do',
    description:
      'Scan threads, triage what matters, and open the exact conversation you need in one place.',
    media: { src: '/onboarding/step2.mp4', type: 'video' as const },
  },
  {
    title: 'Draft replies with less effort',
    description:
      'Use AI to summarize threads, draft responses, and get unstuck without leaving your inbox.',
    media: { src: '/onboarding/step1.mp4', type: 'video' as const },
  },
  {
    title: 'Stay organized as you go',
    description: 'Star, archive, and label messages so your inbox stays easy to understand.',
    media: { src: '/onboarding/step3.mp4', type: 'video' as const },
  },
  {
    title: 'Ready to start?',
    description: 'Connect your inbox when you are ready, or explore the workspace first.',
    media: { src: '/onboarding/ready.png', type: 'image' as const },
  },
];

export function OnboardingDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const [currentStep, setCurrentStep] = useState(0);

  // Reset to step 0 whenever the dialog closes so reopening starts fresh.
  useEffect(() => {
    if (!open) setCurrentStep(0);
  }, [open]);

  // Confetti only when the dialog is actually visible AND the user reaches the
  // last step (not on a remount that lands on the last step).
  useEffect(() => {
    if (!open) return;
    if (currentStep !== steps.length - 1) return;
    confetti({
      particleCount: 100,
      spread: 70,
      origin: { y: 0.6 },
    });
    return () => {
      confetti.reset();
    };
  }, [currentStep, open]);

  const handleNext = () => {
    if (currentStep < steps.length - 1) {
      setCurrentStep(currentStep + 1);
    } else {
      onOpenChange(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogTitle></DialogTitle>
      <DialogContent
        showOverlay
        className="bg-panelLight mx-auto w-full max-w-[90%] rounded-xl border p-0 sm:max-w-[690px] dark:bg-[#111111]"
      >
        <div className="flex flex-col gap-4 p-4">
          {steps[currentStep]?.media && (
            <div className="relative flex items-center justify-center">
              <div className="bg-muted aspect-video w-full max-w-4xl overflow-hidden rounded-lg">
                {steps[currentStep].media.type === 'video' ? (
                  <video
                    key={steps[currentStep].media.src}
                    autoPlay
                    loop
                    muted
                    playsInline
                    preload="auto"
                    aria-label={steps[currentStep].title}
                    className="h-full w-full rounded-lg border object-cover"
                  >
                    <source src={steps[currentStep].media.src} type="video/mp4" />
                  </video>
                ) : (
                  <img
                    loading="eager"
                    width={500}
                    height={500}
                    src={steps[currentStep].media.src}
                    alt={steps[currentStep].title}
                    className="h-full w-full rounded-lg border object-cover"
                  />
                )}
              </div>
            </div>
          )}
          <div className="space-y-0">
            <h2 className="text-4xl font-semibold">{steps[currentStep]?.title}</h2>
            <p className="text-muted-foreground max-w-xl text-sm">
              {steps[currentStep]?.description}
            </p>
          </div>

          <div className="mx-auto flex w-full justify-between">
            <div className="flex gap-2">
              <Button
                size={'xs'}
                onClick={() => setCurrentStep(currentStep - 1)}
                variant="outline"
                disabled={currentStep === 0}
              >
                Go back
              </Button>
              <Button size={'xs'} onClick={handleNext}>
                {currentStep === steps.length - 1 ? 'Get Started' : 'Next'}
              </Button>
            </div>
            <div className="flex items-center justify-center">
              <div className="flex gap-1">
                {steps.map((_, index) => (
                  <div
                    key={_.title}
                    className={`h-1 w-4 rounded-full md:w-10 ${
                      index === currentStep ? 'bg-primary' : 'bg-muted'
                    }`}
                  />
                ))}
              </div>
            </div>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}

export function OnboardingWrapper() {
  const [showOnboarding, setShowOnboarding] = useState(false);
  const { isLoading } = useConnections();
  const { data: session } = useSession();
  const userId = session?.user?.id as string | undefined;
  const ONBOARDING_KEY = onboardingKeyForUser(userId);

  useEffect(() => {
    if (isLoading) return;
    if (!userId) return;

    // Wrap localStorage in try/catch — Safari private browsing & some
    // cookie-blocked iOS setups throw on access.
    let hasCompletedOnboarding = false;
    try {
      hasCompletedOnboarding = localStorage.getItem(ONBOARDING_KEY) === 'true';
    } catch {
      // No storage — assume first run; the tour opens once per session.
    }

    setShowOnboarding(!hasCompletedOnboarding);

    // Sync across tabs: if tab A finishes onboarding, tab B should close it too.
    const onStorage = (e: StorageEvent) => {
      if (e.key === ONBOARDING_KEY && e.newValue === 'true') {
        setShowOnboarding(false);
      }
    };
    window.addEventListener('storage', onStorage);
    return () => window.removeEventListener('storage', onStorage);
  }, [isLoading, userId, ONBOARDING_KEY]);

  const handleOpenChange = (open: boolean) => {
    if (!open) {
      try {
        localStorage.setItem(ONBOARDING_KEY, 'true');
      } catch {
        // Ignore — without storage we re-show the tour next time, which is harmless.
      }
      // Notify same-tab listeners (storage event only fires cross-tab) so the
      // connection prompt can render now that onboarding finished.
      try {
        window.dispatchEvent(new Event('onboarding-completed'));
      } catch {
        // No-op in non-browser environments.
      }
    }
    setShowOnboarding(open);
  };

  return <OnboardingDialog open={showOnboarding} onOpenChange={handleOpenChange} />;
}

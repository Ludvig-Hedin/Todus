import { Dialog, DialogContent, DialogTitle } from '@/components/ui/dialog';
import { useConnections } from '@/hooks/use-connections';
import { Button } from '@/components/ui/button';
import { useState, useEffect } from 'react';
import { APP_NAME } from '@/lib/branding';
import confetti from 'canvas-confetti';

const steps = [
  {
    title: `Welcome to ${APP_NAME}`,
    description:
      'Process inbox work faster with clearer threads, quicker replies, and built-in AI help.',
    video: '/onboarding/get-started.png',
  },
  {
    title: 'Find the next thing to do',
    description:
      'Scan threads, triage what matters, and open the exact conversation you need in one place.',
    video: '/onboarding/step2.gif',
  },
  {
    title: 'Draft replies with less effort',
    description:
      'Use AI to summarize threads, draft responses, and get unstuck without leaving your inbox.',
    video: '/onboarding/step1.gif',
  },
  {
    title: 'Stay organized as you go',
    description: 'Star, archive, and label messages so your inbox stays easy to understand.',
    video: '/onboarding/step3.gif',
  },
  {
    title: 'Ready to start?',
    description: 'Connect your inbox when you are ready, or explore the workspace first.',
    video: '/onboarding/ready.png',
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

  useEffect(() => {
    if (currentStep === steps.length - 1) {
      confetti({
        particleCount: 100,
        spread: 70,
        origin: { y: 0.6 },
      });
    }
  }, [currentStep]);

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
          {steps[currentStep] && steps[currentStep].video && (
            <div className="relative flex items-center justify-center">
              <div className="bg-muted aspect-video w-full max-w-4xl overflow-hidden rounded-lg">
                {steps.map(
                  (step, index) =>
                    step.video && (
                      <div
                        key={step.title}
                        className={`absolute inset-0 transition-opacity duration-300 ${
                          index === currentStep ? 'opacity-100' : 'opacity-0'
                        }`}
                      >
                        <img
                          loading="eager"
                          width={500}
                          height={500}
                          src={step.video}
                          alt={step.title}
                          className="h-full w-full rounded-lg border object-cover"
                        />
                      </div>
                    ),
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
  const ONBOARDING_KEY = 'hasCompletedOnboarding';
  const { data: connectionsData, isLoading } = useConnections();

  useEffect(() => {
    if (isLoading) return;

    const hasCompletedOnboarding = localStorage.getItem(ONBOARDING_KEY) === 'true';
    const hasConnections = (connectionsData?.connections.length ?? 0) > 0;

    // Show the tour only after the user has at least one connected inbox.
    // Otherwise the connect prompt and onboarding compete for attention on first run.
    setShowOnboarding(hasConnections && !hasCompletedOnboarding);
  }, [connectionsData?.connections.length, isLoading]);

  const handleOpenChange = (open: boolean) => {
    if (!open) {
      localStorage.setItem(ONBOARDING_KEY, 'true');
    }
    setShowOnboarding(open);
  };

  return <OnboardingDialog open={showOnboarding} onOpenChange={handleOpenChange} />;
}

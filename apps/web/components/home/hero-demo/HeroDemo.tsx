import { useReducedMotion } from 'motion/react';
import { cn } from '@/lib/utils';
import { SCENES } from './mockData';
import { useSceneLoop } from './useSceneLoop';
import { DemoSidebar } from './DemoSidebar';
import { DemoMobileTabs } from './DemoMobileTabs';
import { DemoStage } from './DemoStage';

interface HeroDemoProps {
  variant?: 'desktop' | 'mobile';
  className?: string;
}

export function HeroDemo({ variant = 'desktop', className }: HeroDemoProps) {
  const reducedMotion = useReducedMotion();
  const { activeScene, selectScene } = useSceneLoop(SCENES, 5500, !reducedMotion);

  if (variant === 'mobile') {
    return (
      <div
        role="region"
        aria-label="Product demo"
        className={cn(
          'relative w-full overflow-hidden rounded-2xl border border-white/[0.08] bg-[#1C1C1E] shadow-xl shadow-black/40',
          className,
        )}
      >
        <DemoMobileTabs active={activeScene} onSelect={selectScene} />
        <div className="relative h-[460px]">
          <DemoStage active={activeScene} compact />
        </div>
      </div>
    );
  }

  return (
    <div
      role="region"
      aria-label="Product demo"
      className={cn(
        'relative w-full overflow-hidden rounded-2xl border border-white/[0.08] bg-[#1C1C1E] shadow-2xl shadow-black/50',
        className,
      )}
    >
      <div className="flex aspect-[7/5] w-full">
        <DemoSidebar active={activeScene} onSelect={selectScene} />
        <div className="relative min-w-0 flex-1 overflow-hidden">
          <DemoStage active={activeScene} />
        </div>
      </div>
    </div>
  );
}

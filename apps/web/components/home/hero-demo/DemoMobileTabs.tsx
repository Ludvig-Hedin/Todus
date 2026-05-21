import { motion } from 'motion/react';
import { Inbox, Calendar, CheckSquare, Sparkles } from 'lucide-react';
import { cn } from '@/lib/utils';
import type { SceneId } from './mockData';

const items: { id: SceneId; label: string; icon: React.ComponentType<{ className?: string }> }[] = [
  { id: 'mail', label: 'Inbox', icon: Inbox },
  { id: 'calendar', label: 'Calendar', icon: Calendar },
  { id: 'tasks', label: 'Tasks', icon: CheckSquare },
  { id: 'assistant', label: 'AI', icon: Sparkles },
];

export function DemoMobileTabs({
  active,
  onSelect,
}: {
  active: SceneId;
  onSelect: (id: SceneId) => void;
}) {
  return (
    <nav
      aria-label="Demo navigation"
      className="flex shrink-0 items-center gap-1 border-b border-border/70 bg-background/40 px-2 py-2"
    >
      {items.map((item) => {
        const Icon = item.icon;
        const isActive = active === item.id;
        return (
          <button
            key={item.id}
            type="button"
            onClick={() => onSelect(item.id)}
            aria-label={`Show ${item.label}`}
            aria-pressed={isActive}
            className="relative flex flex-1 items-center justify-center gap-1.5 rounded-lg px-2 py-1.5 text-[11px] font-medium text-muted-foreground"
          >
            {isActive && (
              <motion.span
                layoutId="demo-tabs-active"
                className="absolute inset-0 rounded-lg bg-foreground/10"
                transition={{ type: 'spring', stiffness: 380, damping: 32 }}
              />
            )}
            <Icon className={cn('relative h-3.5 w-3.5', isActive && 'text-foreground')} />
            <span className={cn('relative', isActive && 'text-foreground')}>{item.label}</span>
          </button>
        );
      })}
    </nav>
  );
}

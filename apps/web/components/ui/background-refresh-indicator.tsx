import { RefreshCw } from 'lucide-react';
import { cn } from '@/lib/utils';

export function BackgroundRefreshIndicator({
  label = 'Updating',
  className,
}: {
  label?: string;
  className?: string;
}) {
  return (
    <div
      className={cn(
        'inline-flex items-center gap-1.5 rounded-full border bg-background/90 px-2 py-1 text-[11px] font-medium text-muted-foreground shadow-sm backdrop-blur-sm',
        className,
      )}
      aria-live="polite"
    >
      <RefreshCw className="h-3 w-3 animate-spin" />
      <span>{label}</span>
    </div>
  );
}

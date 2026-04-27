import { WifiOff } from 'lucide-react';
import { useNetworkStatus } from '~/hooks/use-network-status';

export function OfflineIndicator() {
  const { isOnline } = useNetworkStatus();
  if (isOnline) return null;

  return (
    <div className="flex items-center gap-1.5 bg-muted/60 backdrop-blur-sm px-3 py-1.5 text-xs text-muted-foreground border-b border-border/50">
      <WifiOff className="size-3 shrink-0" />
      <span>You're offline — changes will sync when reconnected</span>
    </div>
  );
}

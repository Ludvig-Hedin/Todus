import { useEffect, useState } from 'react';

export function useNetworkStatus() {
  // Default to true for SSR. The effect below corrects the value on mount so
  // a user who loads the page while offline sees the indicator immediately
  // rather than waiting for the next online/offline event.
  const [isOnline, setIsOnline] = useState(true);

  useEffect(() => {
    setIsOnline(navigator.onLine);
    const handleOnline = () => setIsOnline(true);
    const handleOffline = () => setIsOnline(false);
    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);
    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);

  return { isOnline };
}

import { startTransition, StrictMode } from 'react';
import { HydratedRouter } from 'react-router/dom';
import { hydrateRoot } from 'react-dom/client';
import * as Sentry from '@sentry/react';
import './instrument';

startTransition(() => {
  hydrateRoot(
    document,
    <StrictMode>
      <HydratedRouter />
    </StrictMode>,
    {
      onUncaughtError: Sentry.reactErrorHandler((error, errorInfo) => {
        console.warn('Uncaught error', error, errorInfo.componentStack);
      }),
      // Callback called when React catches an error in an ErrorBoundary.
      onCaughtError: Sentry.reactErrorHandler(),
      // Callback called when React automatically recovers from errors.
      onRecoverableError: Sentry.reactErrorHandler(),
    },
  );
});

// Register the web push service worker. Registration alone does not prompt for
// notification permission — that happens only when the user enables push from
// Settings → Notifications. We register here so the SW is ready to receive
// pushes once a subscription exists. Failures are non-fatal.
if (typeof window !== 'undefined' && 'serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch((error) => {
      console.warn('[sw] registration failed', error);
    });
  });
}

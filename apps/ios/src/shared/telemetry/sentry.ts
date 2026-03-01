/**
 * Native Sentry client bootstrap and helpers.
 */
import * as Sentry from '@sentry/react-native';

let sentryInitialized = false;

export function initSentry(config: { dsn?: string; tunnel?: string }) {
  if (!config.dsn || sentryInitialized) {
    return;
  }

  Sentry.init({
    dsn: config.dsn,
    tunnel: config.tunnel,
    debug: false,
    tracesSampleRate: 1.0,
  });

  sentryInitialized = true;
}

export function captureSentryException(error: unknown, context?: Record<string, unknown>) {
  Sentry.captureException(error, context ? { extra: context } : undefined);
}

/**
 * Sentry stubs — Sentry has been removed from the iOS app to eliminate
 * Xcode build errors caused by missing org/project config. These no-op
 * functions keep existing call sites from breaking.
 * If you re-add Sentry later, replace these stubs with real implementations.
 */

export function initSentry(_config: { dsn?: string; tunnel?: string }) {
  // No-op: Sentry is not installed
}

export function captureSentryException(_error: unknown, _context?: Record<string, unknown>) {
  // No-op: Sentry is not installed — errors are only logged to console
  if (__DEV__) {
    console.warn('[Sentry stub] captureSentryException called but Sentry is not installed:', _error);
  }
}

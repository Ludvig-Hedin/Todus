/**
 * Environment configuration for the native Expo app.
 * Uses EXPO_PUBLIC_* env vars (available at build time in Expo).
 */
// Must match the server's VITE_PUBLIC_BACKEND_URL / VITE_PUBLIC_APP_URL in production.
const DEFAULT_BACKEND_URL = 'https://api.todus.app';
const DEFAULT_WEB_URL = 'https://todus.app';
const DEFAULT_APP_NAME = 'Todus';
const NATIVE_APP_USER_AGENT = 'TodusNative/1.0';

export type NativeEnv = {
  appName: string;
  backendUrl: string;
  webUrl: string;
  posthogKey: string;
  posthogHost: string;
  sentryDsn: string;
  appEntryPath: string;
  appEntryUrl: string;
  authCallbackUrl: string;
  userAgent: string;
  allowedHosts: string[];
  authBypassEnabled: boolean;
};

function parseHost(input: string): string | null {
  try {
    return new URL(input).host;
  } catch {
    return null;
  }
}

function isTruthyEnv(value: string | undefined): boolean {
  if (!value) return false;
  const normalized = value.trim().toLowerCase();
  return normalized === '1' || normalized === 'true' || normalized === 'yes' || normalized === 'on';
}

export function getNativeEnv(): NativeEnv {
  const backendUrl = process.env.EXPO_PUBLIC_BACKEND_URL ?? DEFAULT_BACKEND_URL;
  const webUrl = process.env.EXPO_PUBLIC_WEB_URL ?? DEFAULT_WEB_URL;
  const posthogKey = process.env.EXPO_PUBLIC_POSTHOG_KEY ?? '';
  const posthogHost = process.env.EXPO_PUBLIC_POSTHOG_HOST ?? 'https://us.i.posthog.com';
  const sentryDsn = process.env.EXPO_PUBLIC_SENTRY_DSN ?? '';
  const appEntryPath = '/mail/inbox';
  const appName = process.env.EXPO_PUBLIC_APP_NAME ?? DEFAULT_APP_NAME;
  const appEntryUrl = `${webUrl.replace(/\/$/, '')}${appEntryPath}`;
  // Must use the web app URL (not the API URL) so after OAuth the browser
  // lands on the web app. The origin must be in the server's trustedOrigins.
  const authCallbackUrl = `${webUrl.replace(/\/$/, '')}/mail/inbox`;
  const authBypassEnabled = isTruthyEnv(process.env.EXPO_PUBLIC_AUTH_BYPASS);

  const allowedHosts = Array.from(
    new Set(
      [
        parseHost(webUrl),
        parseHost(backendUrl),
        'accounts.google.com',
        'oauth2.googleapis.com',
      ].filter((value): value is string => Boolean(value)),
    ),
  );

  return {
    appName,
    backendUrl,
    webUrl,
    posthogKey,
    posthogHost,
    sentryDsn,
    appEntryPath,
    appEntryUrl,
    authCallbackUrl,
    userAgent: NATIVE_APP_USER_AGENT,
    allowedHosts,
    authBypassEnabled,
  };
}

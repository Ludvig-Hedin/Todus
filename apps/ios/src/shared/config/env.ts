/**
 * Environment configuration for the native Expo app.
 * Uses EXPO_PUBLIC_* env vars (available at build time in Expo).
 */
const DEFAULT_BACKEND_URL = 'https://todus-server-v1-production.ludvighedin15.workers.dev';
const DEFAULT_WEB_URL = 'https://todus-production.ludvighedin15.workers.dev';
const DEFAULT_APP_NAME = 'Todus';
const NATIVE_APP_USER_AGENT = 'TodusNative/1.0';

export type NativeEnv = {
  appName: string;
  backendUrl: string;
  webUrl: string;
  appEntryPath: string;
  appEntryUrl: string;
  authCallbackUrl: string;
  userAgent: string;
  allowedHosts: string[];
};

function parseHost(input: string): string | null {
  try {
    return new URL(input).host;
  } catch {
    return null;
  }
}

export function getNativeEnv(): NativeEnv {
  const backendUrl = process.env.EXPO_PUBLIC_BACKEND_URL ?? DEFAULT_BACKEND_URL;
  const webUrl = process.env.EXPO_PUBLIC_WEB_URL ?? DEFAULT_WEB_URL;
  const appEntryPath = '/mail/inbox';
  const appName = process.env.EXPO_PUBLIC_APP_NAME ?? DEFAULT_APP_NAME;
  const appEntryUrl = `${webUrl.replace(/\/$/, '')}${appEntryPath}`;
  const authCallbackUrl = `${webUrl.replace(/\/$/, '')}/mail/inbox`;

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
    appEntryPath,
    appEntryUrl,
    authCallbackUrl,
    userAgent: NATIVE_APP_USER_AGENT,
    allowedHosts,
  };
}

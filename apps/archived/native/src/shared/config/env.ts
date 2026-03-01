const DEFAULT_BACKEND_URL = 'https://api.todus.app';
const DEFAULT_WEB_URL = 'https://todus.app';
const DEFAULT_APP_NAME = 'Todus';
const DEFAULT_AUTH_CALLBACK_URL = `${DEFAULT_WEB_URL}/mail/inbox`;
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
  const backendUrl = process.env.ZERO_PUBLIC_BACKEND_URL ?? DEFAULT_BACKEND_URL;
  const webUrl = process.env.ZERO_PUBLIC_WEB_URL ?? DEFAULT_WEB_URL;
  const appEntryPath = process.env.ZERO_PUBLIC_APP_ENTRY_PATH ?? '/mail/inbox';
  const authCallbackUrl = process.env.ZERO_PUBLIC_AUTH_CALLBACK_URL ?? DEFAULT_AUTH_CALLBACK_URL;
  const appName = process.env.ZERO_PUBLIC_APP_NAME ?? DEFAULT_APP_NAME;
  const appEntryUrl = `${webUrl.replace(/\/$/, '')}${appEntryPath.startsWith('/') ? appEntryPath : `/${appEntryPath}`}`;

  const allowedHosts = Array.from(
    new Set(
      [parseHost(webUrl), parseHost(backendUrl), 'accounts.google.com', 'oauth2.googleapis.com'].filter(
        (value): value is string => Boolean(value),
      ),
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

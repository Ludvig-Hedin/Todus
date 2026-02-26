/**
 * Native auth helper functions for OAuth and session management.
 * Handles provider loading, sign-in initiation, token parsing, and validation.
 */
import {
  nativeRouteDefaults,
  normalizeWebPath,
  routeRequiresAuth,
  type NativeAuthProvider,
} from '@zero/shared';

type ParsedAuthCallback = {
  token: string | null;
  expiresAt: number | null;
};

/** Fetches available auth providers from the backend */
export async function loadNativeAuthProviders(baseUrl: string): Promise<NativeAuthProvider[]> {
  const response = await fetch(`${baseUrl.replace(/\/$/, '')}/api/public/providers`);
  if (!response.ok) {
    throw new Error(`Failed to load providers (${response.status})`);
  }

  const payload = (await response.json()) as { allProviders: NativeAuthProvider[] };

  return payload.allProviders
    .filter((provider) => provider.enabled || provider.isCustom)
    .sort((left, right) => {
      if (left.id === 'zero') return -1;
      if (right.id === 'zero') return 1;
      return left.name.localeCompare(right.name);
    });
}

/** Initiates OAuth sign-in and returns the authorization URL */
export async function beginNativeProviderSignIn(
  baseUrl: string,
  providerId: string,
  callbackUrl: string,
): Promise<string> {
  const response = await fetch(`${baseUrl.replace(/\/$/, '')}/api/auth/sign-in/social`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      provider: providerId,
      callbackURL: callbackUrl,
      disableRedirect: true,
    }),
  });
  if (!response.ok) {
    throw new Error(`Provider sign-in failed (${response.status})`);
  }

  const payload = (await response.json()) as { url?: string };

  if (payload.url) {
    return payload.url;
  }

  throw new Error('Provider did not return an authorization URL.');
}

/** Extracts bearer token from OAuth callback URL parameters */
export function parseAuthCallback(rawUrl: string): ParsedAuthCallback {
  try {
    const url = new URL(rawUrl);
    const token =
      url.searchParams.get('token') ??
      url.searchParams.get('set-auth-token') ??
      url.searchParams.get('authToken');
    const expiresRaw =
      url.searchParams.get('expiresAt') ??
      url.searchParams.get('expires_at') ??
      url.searchParams.get('exp');

    if (!token) {
      return { token: null, expiresAt: null };
    }

    const expiresAt = expiresRaw ? Number(expiresRaw) : null;

    return {
      token,
      expiresAt: Number.isFinite(expiresAt) ? expiresAt : null,
    };
  } catch {
    return { token: null, expiresAt: null };
  }
}

/** Checks if a URL is within the allowed hosts list */
export function isAllowedWebUrl(rawUrl: string, allowedHosts: string[]): boolean {
  if (rawUrl === 'about:blank') return true;

  try {
    const url = new URL(rawUrl);
    if (url.protocol !== 'https:' && url.protocol !== 'http:') {
      return false;
    }

    return allowedHosts.includes(url.host);
  } catch {
    return false;
  }
}

/** Checks if a URL points to an authenticated route in the web app */
export function isSignedInPath(rawUrl: string, appOrigin: string): boolean {
  try {
    const appHost = new URL(appOrigin).host;
    const url = new URL(rawUrl);
    if (url.host !== appHost) {
      return false;
    }

    return routeRequiresAuth(url.pathname);
  } catch {
    return false;
  }
}

/** Checks if a URL points to the login page */
export function isLoginPath(rawUrl: string, appOrigin: string): boolean {
  try {
    const appHost = new URL(appOrigin).host;
    const url = new URL(rawUrl);
    if (url.host !== appHost) {
      return false;
    }

    return normalizeWebPath(url.pathname).startsWith(nativeRouteDefaults.loginPath);
  } catch {
    return false;
  }
}

/** Validates a bearer token against the backend, returns refreshed token or null */
export async function validateBearerToken(baseUrl: string, token: string): Promise<string | null> {
  const response = await fetch(`${baseUrl.replace(/\/$/, '')}/api/auth/get-session`, {
    headers: {
      Authorization: `Bearer ${token}`,
    },
  });
  if (!response.ok) {
    return null;
  }

  return response.headers.get('set-auth-token') ?? token;
}

/** Extracts the web path from a full URL */
export function resolveWebPathFromUrl(rawUrl: string): string {
  try {
    const url = new URL(rawUrl);
    return normalizeWebPath(`${url.pathname}${url.search}`);
  } catch {
    return nativeRouteDefaults.appEntryPath;
  }
}

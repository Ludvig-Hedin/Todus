import { QueryCache, QueryClient } from '@tanstack/react-query';
import { createTRPCClient, httpBatchLink } from '@trpc/client';
import type { AnyRouter } from '@trpc/server';
import type { AppRouter } from '@zero/server/trpc';
import type { NativeAuthProvider } from '@zero/shared';
import superjson from 'superjson';

export type { AppRouter };

export type HeaderFactory =
  | Record<string, string>
  | undefined
  | (() => Record<string, string> | undefined | Promise<Record<string, string> | undefined>);

export type ZeroTrpcClientOptions = {
  baseUrl: string;
  getHeaders?: HeaderFactory;
  includeCredentials?: boolean;
  maxItems?: number;
  onUnauthorized?: () => void;
};

async function resolveHeaders(getHeaders: HeaderFactory): Promise<Record<string, string>> {
  if (!getHeaders) return {};
  if (typeof getHeaders === 'function') {
    return (await getHeaders()) ?? {};
  }
  return getHeaders;
}

export function buildTrpcUrl(baseUrl: string): string {
  return `${baseUrl.replace(/\/$/, '')}/api/trpc`;
}

export function createZeroTrpcClient<TRouter extends AnyRouter = AppRouter>(
  options: ZeroTrpcClientOptions,
) {
  return createTRPCClient<TRouter>({
    links: [
      httpBatchLink({
        url: buildTrpcUrl(options.baseUrl),
        transformer: superjson as any,
        maxItems: options.maxItems ?? 1,
        async fetch(url, requestInit) {
          const headers = {
            ...(requestInit?.headers ?? {}),
            ...(await resolveHeaders(options.getHeaders)),
          } as HeadersInit;

          const response = await fetch(url, {
            ...requestInit,
            headers,
            credentials: options.includeCredentials ? 'include' : 'omit',
          });

          if (response.status === 401) {
            options.onUnauthorized?.();
          }

          return response;
        },
      }),
    ],
  });
}

export function createZeroQueryClient() {
  return new QueryClient({
    queryCache: new QueryCache({
      onError: (error) => {
        console.error('[query-error]', error);
      },
    }),
    defaultOptions: {
      queries: {
        retry: false,
        refetchOnWindowFocus: false,
      },
      mutations: {
        retry: false,
      },
    },
  });
}

export type PublicProvidersResponse = {
  allProviders: NativeAuthProvider[];
  isProd: boolean;
};

export type SocialSignInResponse =
  | {
    url: string;
    redirect: boolean;
  }
  | {
    redirect: false;
    token: string;
    url?: string;
    user?: unknown;
  };

export type NativeSessionResult = {
  ok: boolean;
  nextToken: string | null;
};

function buildAuthUrl(baseUrl: string, path: string): string {
  return `${baseUrl.replace(/\/$/, '')}/api/auth${path}`;
}

function buildPublicUrl(baseUrl: string, path: string): string {
  return `${baseUrl.replace(/\/$/, '')}/api/public${path}`;
}

export async function fetchNativeAuthProviders(baseUrl: string): Promise<PublicProvidersResponse> {
  const response = await fetch(buildPublicUrl(baseUrl, '/providers'));
  if (!response.ok) {
    throw new Error(`Failed to load providers (${response.status})`);
  }

  return (await response.json()) as PublicProvidersResponse;
}

export async function requestSocialSignIn(
  baseUrl: string,
  provider: string,
  callbackURL: string,
): Promise<SocialSignInResponse> {
  const response = await fetch(buildAuthUrl(baseUrl, '/sign-in/social'), {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      provider,
      callbackURL,
      disableRedirect: true,
    }),
  });

  if (!response.ok) {
    throw new Error(`Social sign-in request failed (${response.status})`);
  }

  return (await response.json()) as SocialSignInResponse;
}

export async function validateNativeBearerSession(
  baseUrl: string,
  token: string,
): Promise<NativeSessionResult> {
  const response = await fetch(buildAuthUrl(baseUrl, '/get-session'), {
    headers: {
      Authorization: `Bearer ${token}`,
    },
  });

  if (!response.ok) {
    return { ok: false, nextToken: null };
  }

  const nextToken = response.headers.get('set-auth-token');
  return {
    ok: true,
    nextToken: nextToken ?? token,
  };
}

export async function signOutNativeSession(baseUrl: string, token?: string | null): Promise<boolean> {
  const response = await fetch(buildAuthUrl(baseUrl, '/sign-out'), {
    method: 'POST',
    headers: token
      ? {
        Authorization: `Bearer ${token}`,
      }
      : undefined,
  });

  return response.ok;
}

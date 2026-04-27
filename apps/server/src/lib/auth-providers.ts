import { type JWTPayload, decodeProtectedHeader, importJWK, jwtVerify } from 'jose';

export interface EnvVarInfo {
  name: string;
  source: string;
  defaultValue?: string;
}

export interface ProviderConfig {
  id: string;
  name: string;
  requiredEnvVars: string[];
  envVarInfo?: EnvVarInfo[];
  config: unknown;
  required?: boolean;
  isCustom?: boolean;
  customRedirectPath?: string;
}

// Bundle IDs allowed to sign in via native Apple Sign-in. The iOS and macOS
// apps each request the ID token with their own bundle identifier as the
// audience claim, so Better Auth must accept both. Better Auth's built-in
// verifier only takes a single `appBundleIdentifier`, so we plug a custom
// verifier that whitelists the array.
const APPLE_ALLOWED_AUDIENCES = ['com.ludvighedin.todus', 'com.ludvighedin.todus.macos'];

// Cache resolved JWKs so we don't refetch Apple's JWKS endpoint on every
// sign-in. Apple rotates keys infrequently; if a `kid` misses, we refetch.
let appleKeyCache: Map<string, Awaited<ReturnType<typeof importJWK>>> | null = null;
let appleJwksFetchedAt = 0;
const APPLE_JWKS_TTL_MS = 60 * 60 * 1000; // 1 hour

const refreshAppleJwks = async () => {
  const res = await fetch('https://appleid.apple.com/auth/keys');
  if (!res.ok) {
    throw new Error(`Apple JWKS fetch failed: ${res.status}`);
  }
  const data = (await res.json()) as { keys: Array<{ kid: string; alg: string }> };
  const cache = new Map<string, Awaited<ReturnType<typeof importJWK>>>();
  for (const key of data.keys) {
    cache.set(key.kid, await importJWK(key, key.alg));
  }
  appleKeyCache = cache;
  appleJwksFetchedAt = Date.now();
};

const getAppleKey = async (kid: string) => {
  const stale = !appleKeyCache || Date.now() - appleJwksFetchedAt > APPLE_JWKS_TTL_MS;
  if (stale || !appleKeyCache?.has(kid)) {
    await refreshAppleJwks();
  }
  const key = appleKeyCache?.get(kid);
  if (!key) {
    // Force a refresh on miss in case Apple rotated keys since the cached fetch.
    await refreshAppleJwks();
  }
  return appleKeyCache?.get(kid);
};

export type AppleIdTokenPayload = JWTPayload & {
  sub: string;
  email?: string;
  email_verified?: boolean | string;
  name?: string;
};

export const verifyAppleIdTokenPayload = async (
  token: string,
  nonce?: string,
): Promise<AppleIdTokenPayload | null> => {
  try {
    const header = decodeProtectedHeader(token);
    const { kid, alg } = header;
    if (!kid || !alg) {
      console.error('[apple verifyIdToken] missing kid/alg in token header', { kid, alg });
      return null;
    }
    const publicKey = await getAppleKey(kid);
    if (!publicKey) {
      console.error('[apple verifyIdToken] no JWK found for kid', { kid });
      return null;
    }
    const { payload } = await jwtVerify(token, publicKey, {
      algorithms: [alg],
      issuer: 'https://appleid.apple.com',
      audience: APPLE_ALLOWED_AUDIENCES,
      maxTokenAge: '1h',
    });
    if (nonce && payload.nonce !== nonce) {
      console.error('[apple verifyIdToken] nonce mismatch');
      return null;
    }
    if (!payload.sub) {
      console.error('[apple verifyIdToken] missing subject claim');
      return null;
    }
    return payload as AppleIdTokenPayload;
  } catch (error) {
    // Log the actual cause so the next failure isn't an opaque 500. Returning
    // false here lets Better Auth surface a 401 INVALID_TOKEN instead of an
    // unhandled exception bubbling out as an empty 500.
    console.error('[apple verifyIdToken] validation failed', {
      error: error instanceof Error ? error.message : String(error),
      code: (error as { code?: string })?.code,
      audClaim: (error as { claim?: string })?.claim,
    });
    return null;
  }
};

const verifyAppleIdToken = async (token: string, nonce?: string): Promise<boolean> => {
  return (await verifyAppleIdTokenPayload(token, nonce)) !== null;
};

export const customProviders: ProviderConfig[] = [
  // {
  //   id: "zero",
  //   name: "Zero",
  //   requiredEnvVars: [],
  //   config: {},
  //   isCustom: true,
  //   customRedirectPath: "/zero/signup"
  // }
];

export const authProviders = (env: Record<string, string>): ProviderConfig[] => [
  {
    id: 'google',
    name: 'Google',
    requiredEnvVars: ['GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET'],
    envVarInfo: [
      { name: 'GOOGLE_CLIENT_ID', source: 'Google Cloud Console' },
      { name: 'GOOGLE_CLIENT_SECRET', source: 'Google Cloud Console' },
    ],
    config: {
      // Always force consent so Google returns a refresh_token. Without this,
      // returning users (e.g. mobile after web signup) don't get refresh tokens
      // and the connectionHandlerHook throws "Missing Access/Refresh Tokens".
      prompt: 'consent',
      accessType: 'offline',
      scope: [
        'https://mail.google.com/',
        'https://www.googleapis.com/auth/gmail.modify',
        'https://www.googleapis.com/auth/contacts.readonly',
        'https://www.googleapis.com/auth/contacts.other.readonly',
        'https://www.googleapis.com/auth/userinfo.profile',
        'https://www.googleapis.com/auth/userinfo.email',
        // Must match GoogleMailManager.getScope() so the stored connection scope
        // reflects what the user actually granted. Full calendar scope (read+write)
        // so we can create, update, and delete events on the user's behalf.
        'https://www.googleapis.com/auth/calendar',
      ],
      clientId: env.GOOGLE_CLIENT_ID,
      clientSecret: env.GOOGLE_CLIENT_SECRET,
    },
    required: true,
  },
  //   {
  //     id: 'microsoft',
  //     name: 'Microsoft',
  //     requiredEnvVars: ['MICROSOFT_CLIENT_ID', 'MICROSOFT_CLIENT_SECRET'],
  //     envVarInfo: [
  //       { name: 'MICROSOFT_CLIENT_ID', source: 'Microsoft Azure App ID' },
  //       { name: 'MICROSOFT_CLIENT_SECRET', source: 'Microsoft Azure App Password' },
  //     ],
  //     config: {
  //       clientId: env.MICROSOFT_CLIENT_ID,
  //       clientSecret: env.MICROSOFT_CLIENT_SECRET,
  //       redirectUri: env.MICROSOFT_REDIRECT_URI,
  //       scope: [
  //         'https://graph.microsoft.com/User.Read',
  //         'https://graph.microsoft.com/Mail.ReadWrite',
  //         'https://graph.microsoft.com/Mail.Send',
  //         'offline_access',
  //       ],
  //       authority: 'https://login.microsoftonline.com/common',
  //       responseType: 'code',
  //       prompt: 'consent',
  //       loginHint: 'email',
  //       disableProfilePhoto: true,
  //     },
  //     required: false,
  //   },
  {
    id: 'apple',
    name: 'Apple',
    requiredEnvVars: ['APPLE_CLIENT_ID', 'APPLE_TEAM_ID', 'APPLE_KEY_ID', 'APPLE_PRIVATE_KEY'],
    config: {
      clientId: env.APPLE_CLIENT_ID,
      // Kept for compatibility — Better Auth uses this as fallback audience if
      // `verifyIdToken` is not provided. The custom verifier below is what
      // actually validates production traffic against the multi-bundle list.
      appBundleIdentifier: env.APPLE_APP_BUNDLE_ID || 'com.ludvighedin.todus',
      // Custom validator that accepts both iOS and macOS bundle IDs and
      // converts JWT failures into a `false` return (→ 401) instead of an
      // unhandled throw (→ empty 500 with no logs).
      verifyIdToken: verifyAppleIdToken,
      clientSecret: {
        teamId: env.APPLE_TEAM_ID,
        keyId: env.APPLE_KEY_ID,
        privateKey: env.APPLE_PRIVATE_KEY,
      },
    },
  },
];

export function isProviderEnabled(provider: ProviderConfig, env: Record<string, string>): boolean {
  if (provider.isCustom) return true;

  const hasEnvVars = provider.requiredEnvVars.every((envVar) => !!env[envVar]);

  if (provider.required && !hasEnvVars) {
    console.error(`Required provider "${provider.id}" is not configured properly.`);
    console.error(
      `Missing environment variables: ${provider.requiredEnvVars.filter((envVar) => !env[envVar]).join(', ')}`,
    );
  }

  return hasEnvVars;
}

export function getSocialProviders(env: Record<string, string>) {
  const socialProviders = Object.fromEntries(
    authProviders(env)
      .map((provider) => {
        if (isProviderEnabled(provider, env)) {
          return [provider.id, provider.config] as [string, unknown];
        } else if (provider.required) {
          throw new Error(
            `Required provider "${provider.id}" is not configured properly. Check your environment variables.`,
          );
        } else {
          console.warn(`Provider "${provider.id}" is not configured properly. Skipping.`);
          return null;
        }
      })
      .filter((provider) => provider !== null),
  );
  return socialProviders;
}

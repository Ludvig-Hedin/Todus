/**
 * Jotai atoms for auth session state.
 * Ported from apps/native — manages bearer token lifecycle.
 */
import {
  isNativeAuthSessionExpired,
  nativeRouteDefaults,
  type NativeAuthSession,
} from '@zero/shared';
import { atom } from 'jotai';
import { secureStorage } from '../storage/secure-storage';

export type AuthStatus = 'bootstrapping' | 'authenticated' | 'unauthenticated';

export const sessionAtom = atom<NativeAuthSession | null>(null);
export const authStatusAtom = atom<AuthStatus>('bootstrapping');
export const currentPathAtom = atom<string>(nativeRouteDefaults.appEntryPath);

/** Reads persisted session from secure storage and sets auth status */
export const bootstrapSessionAtom = atom(null, async (_get, set) => {
  const [session, lastVisitedPath] = await Promise.all([
    secureStorage.getSession(),
    secureStorage.getLastVisitedPath(),
  ]);

  if (lastVisitedPath) {
    set(currentPathAtom, lastVisitedPath);
  }

  if (session && !isNativeAuthSessionExpired(session)) {
    set(sessionAtom, session);
    set(authStatusAtom, 'authenticated');
    return;
  }

  set(sessionAtom, null);
  await secureStorage.clearSession();
  set(authStatusAtom, 'unauthenticated');
});

/** Stores a new bearer token session */
export const setBearerSessionAtom = atom(
  null,
  async (_get, set, payload: { token: string; expiresAt?: number | null }) => {
    const session: NativeAuthSession = {
      mode: 'bearer',
      token: payload.token,
      createdAt: Date.now(),
      expiresAt: payload.expiresAt ?? null,
    };
    await secureStorage.setSession(session);
    set(sessionAtom, session);
    set(authStatusAtom, 'authenticated');
  },
);

/** Stores a web-cookie session (no token, relies on cookies) */
export const setWebCookieSessionAtom = atom(null, async (_get, set) => {
  const session: NativeAuthSession = {
    mode: 'web-cookie',
    token: null,
    createdAt: Date.now(),
    expiresAt: null,
  };
  await secureStorage.setSession(session);
  set(sessionAtom, session);
  set(authStatusAtom, 'authenticated');
});

/** Clears the session and resets to unauthenticated */
export const clearSessionAtom = atom(null, async (_get, set) => {
  await secureStorage.clearSession();
  set(sessionAtom, null);
  set(authStatusAtom, 'unauthenticated');
});

/** Persists the current path so it can be restored on next launch */
export const setCurrentPathAtom = atom(null, async (_get, set, path: string) => {
  await secureStorage.setLastVisitedPath(path);
  set(currentPathAtom, path);
});

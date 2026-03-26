/**
 * SessionBootstrap — validates auth session on app start and when returning from background.
 * Refreshes bearer tokens if the server issues a new one via set-auth-token header.
 */
import { getNativeEnv } from '../shared/config/env';
import { validateBearerToken } from '../features/auth/native-auth';
import { useAtomValue, useSetAtom } from 'jotai';
import { useEffect, type PropsWithChildren } from 'react';
import { AppState } from 'react-native';
import {
  bootstrapSessionAtom,
  clearSessionAtom,
  sessionAtom,
  setBearerSessionAtom,
  setPreviewBypassSessionAtom,
} from '../shared/state/session';

export function SessionBootstrap({ children }: PropsWithChildren) {
  const env = getNativeEnv();
  const session = useAtomValue(sessionAtom);
  const bootstrapSession = useSetAtom(bootstrapSessionAtom);
  const clearSession = useSetAtom(clearSessionAtom);
  const setBearerSession = useSetAtom(setBearerSessionAtom);
  const setPreviewBypassSession = useSetAtom(setPreviewBypassSessionAtom);

  // Bootstrap session from secure storage on mount
  useEffect(() => {
    if (env.authBypassEnabled) {
      setPreviewBypassSession();
      return;
    }

    bootstrapSession().catch(() => {
      // No-op: bootstrap failures should not crash app init
    });
  }, [bootstrapSession, env.authBypassEnabled, setPreviewBypassSession]);

  // Revalidate bearer token on mount and when app returns to foreground
  useEffect(() => {
    if (env.authBypassEnabled) {
      return;
    }

    if (!session || session.mode !== 'bearer' || !session.token) {
      return;
    }

    const revalidateSession = async () => {
      const nextToken = await validateBearerToken(env.backendUrl, session.token as string);
      if (!nextToken) {
        await clearSession();
        return;
      }

      if (nextToken !== session.token) {
        await setBearerSession({ token: nextToken, expiresAt: session.expiresAt ?? null });
      }
    };

    revalidateSession().catch(() => {
      // No-op: session validation failures are handled by guard logic
    });

    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') {
        revalidateSession().catch(() => {});
      }
    });

    return () => {
      subscription.remove();
    };
  }, [clearSession, env.authBypassEnabled, env.backendUrl, session, setBearerSession]);

  return children;
}

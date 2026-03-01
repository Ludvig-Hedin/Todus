import { getNativeEnv } from '../../shared/config/env';
import { validateBearerToken } from '../../features/auth/native-auth';
import { useAtomValue, useSetAtom } from 'jotai';
import { useEffect, type PropsWithChildren } from 'react';
import { AppState } from 'react-native';
import {
  bootstrapSessionAtom,
  clearSessionAtom,
  sessionAtom,
  setBearerSessionAtom,
} from '../../shared/state/session';

export function SessionBootstrap({ children }: PropsWithChildren) {
  const env = getNativeEnv();
  const session = useAtomValue(sessionAtom);
  const bootstrapSession = useSetAtom(bootstrapSessionAtom);
  const clearSession = useSetAtom(clearSessionAtom);
  const setBearerSession = useSetAtom(setBearerSessionAtom);

  useEffect(() => {
    bootstrapSession().catch(() => {
      // No-op: bootstrap failures should not crash app init.
    });
  }, [bootstrapSession]);

  useEffect(() => {
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
      // No-op: session validation failures are handled by guard logic.
    });

    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') {
        revalidateSession().catch(() => {
          // No-op: session validation failures are handled by guard logic.
        });
      }
    });

    return () => {
      subscription.remove();
    };
  }, [clearSession, env.backendUrl, session, setBearerSession]);

  return children;
}

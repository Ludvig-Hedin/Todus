import { phoneNumberClient } from 'better-auth/client/plugins';
import { createAuthClient } from 'better-auth/react';
import type { Auth } from '@zero/server/auth';

// CR-001: Guard with import.meta.env.DEV so Vite tree-shakes the bypass in production builds
const parityAuthBypass =
  import.meta.env.DEV &&
  (String(import.meta.env.VITE_PUBLIC_PARITY_AUTH_BYPASS ?? '').toLowerCase() === '1' ||
    String(import.meta.env.VITE_PUBLIC_PARITY_AUTH_BYPASS ?? '').toLowerCase() === 'true');

export const authClient = createAuthClient({
  baseURL: import.meta.env.VITE_PUBLIC_BACKEND_URL,
  fetchOptions: {
    credentials: 'include',
  },
  plugins: [phoneNumberClient()],
});

const paritySession = {
  user: {
    id: 'parity-bypass-user',
    email: 'parity@todus.app',
    name: 'Parity User',
  },
} as const;

export const signIn = authClient.signIn;
export const signUp = authClient.signUp;
export const signOut = authClient.signOut;
export const $fetch = authClient.$fetch;

export const useSession = parityAuthBypass
  ? (() =>
      ({
        data: paritySession,
        isPending: false,
        error: null,
      }) as any)
  : authClient.useSession;

export const getSession = parityAuthBypass
  ? (async () =>
      ({
        data: paritySession,
        error: null,
      }) as any)
  : authClient.getSession;

export type Session = Awaited<ReturnType<Auth['api']['getSession']>>;

import { createAuthClient } from 'better-auth/client';

const authClient = createAuthClient({
  baseURL: import.meta.env.VITE_PUBLIC_BACKEND_URL,
  fetchOptions: {
    credentials: 'include',
  },
  plugins: [],
});

export const authProxy = {
  api: {
    getSession: async ({ headers }: { headers: Headers }) => {
      // CR-001: Guard with import.meta.env.DEV so Vite tree-shakes the bypass in production builds
      const parityAuthBypass =
        import.meta.env.DEV &&
        (String(import.meta.env.VITE_PUBLIC_PARITY_AUTH_BYPASS ?? '').toLowerCase() === '1' ||
          String(import.meta.env.VITE_PUBLIC_PARITY_AUTH_BYPASS ?? '').toLowerCase() === 'true');

      if (parityAuthBypass) {
        return {
          user: {
            id: 'parity-bypass-user',
            email: 'parity@todus.app',
            name: 'Parity User',
          },
        } as any;
      }

      const session = await authClient.getSession({
        fetchOptions: { headers, credentials: 'include' },
      });
      if (session.error) {
        console.error(`Failed to get session: ${session.error}`, session);
        return null;
      }
      return session.data;
    },
  },
};

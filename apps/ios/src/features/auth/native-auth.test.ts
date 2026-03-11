import { getLinkSocialAuthUrl } from './native-auth';
import assert from 'node:assert/strict';
import test from 'node:test';

type FetchCall = {
  url: string;
  init?: RequestInit;
};

async function withMockedFetch(
  mock: (url: string, init?: RequestInit) => Promise<Response>,
  run: (calls: FetchCall[]) => Promise<void>,
) {
  const originalFetch = globalThis.fetch;
  const calls: FetchCall[] = [];

  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === 'string' ? input : input.toString();
    calls.push({ url, init });
    return mock(url, init);
  }) as typeof fetch;

  try {
    await run(calls);
  } finally {
    globalThis.fetch = originalFetch;
  }
}

test('getLinkSocialAuthUrl posts to /api/auth/native-link-social with bearer auth', async () => {
  await withMockedFetch(
    async () =>
      new Response(null, {
        status: 302,
        headers: {
          Location: 'https://accounts.google.com/o/oauth2/v2/auth?state=abc',
        },
      }),
    async (calls) => {
      const url = await getLinkSocialAuthUrl(
        'https://api.example.com/',
        'https://app.example.com/',
        'token-1',
        'google',
        'https://api.example.com/api/auth/mobile-token',
      );

      assert.equal(url, 'https://accounts.google.com/o/oauth2/v2/auth?state=abc');
      assert.equal(calls.length, 1);
      assert.equal(calls[0].url, 'https://api.example.com/api/auth/native-link-social');

      const headers = calls[0].init?.headers as Record<string, string>;
      assert.equal(headers.Authorization, 'Bearer token-1');
      assert.equal(headers['Content-Type'], 'application/json');
      assert.equal(headers.Origin, 'https://app.example.com');
      assert.equal(calls[0].init?.method, 'POST');
      assert.equal(calls[0].init?.redirect, 'manual');
      assert.deepEqual(JSON.parse(String(calls[0].init?.body)), {
        provider: 'google',
        callbackURL: 'https://api.example.com/api/auth/mobile-token',
        disableRedirect: true,
      });
    },
  );
});

test('getLinkSocialAuthUrl accepts JSON responses with a url field', async () => {
  await withMockedFetch(
    async () =>
      new Response(
        JSON.stringify({ url: 'https://accounts.google.com/o/oauth2/v2/auth?state=xyz' }),
        {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        },
      ),
    async () => {
      const url = await getLinkSocialAuthUrl(
        'https://api.example.com',
        'https://app.example.com',
        'token-2',
        'google',
        'https://api.example.com/api/auth/mobile-token',
      );

      assert.equal(url, 'https://accounts.google.com/o/oauth2/v2/auth?state=xyz');
    },
  );
});

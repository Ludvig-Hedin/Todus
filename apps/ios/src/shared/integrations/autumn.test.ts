import assert from 'node:assert/strict';
import test from 'node:test';
import {
  fetchAutumnCustomer,
  hasAutumnProAccess,
  openAutumnBillingPortal,
  startAutumnCheckout,
} from './autumn';

type FetchCall = {
  url: string;
  init?: RequestInit;
};

function jsonResponse(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

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

test('fetchAutumnCustomer posts to /autumn/customers with bearer auth', async () => {
  await withMockedFetch(
    async () => jsonResponse({ id: 'cus_123' }),
    async (calls) => {
      const customer = await fetchAutumnCustomer('https://api.example.com/', 'token-1');

      assert.equal(customer.id, 'cus_123');
      assert.equal(calls.length, 1);
      assert.equal(calls[0].url, 'https://api.example.com/autumn/customers');
      assert.equal(calls[0].init?.method, 'POST');
      const headers = calls[0].init?.headers as Record<string, string>;
      assert.equal(headers.Authorization, 'Bearer token-1');
      assert.equal(headers['Content-Type'], 'application/json');
      assert.equal(calls[0].init?.body, '{}');
    },
  );
});

test('openAutumnBillingPortal extracts URL from nested payloads', async () => {
  await withMockedFetch(
    async () => jsonResponse({ data: { billing_portal_url: 'https://billing.example.com/portal' } }),
    async () => {
      const url = await openAutumnBillingPortal('https://api.example.com', 'token-2');
      assert.equal(url, 'https://billing.example.com/portal');
    },
  );
});

test('startAutumnCheckout sends product payload and returns checkout URL', async () => {
  await withMockedFetch(
    async () => jsonResponse({ checkout_url: 'https://billing.example.com/checkout' }),
    async (calls) => {
      const url = await startAutumnCheckout('https://api.example.com', 'token-3', {
        productId: 'pro_annual',
        successUrl: 'https://todus.app/mail/inbox?success=true',
      });

      assert.equal(url, 'https://billing.example.com/checkout');
      assert.equal(calls.length, 1);
      assert.equal(calls[0].url, 'https://api.example.com/autumn/attach');
      assert.deepEqual(JSON.parse(String(calls[0].init?.body)), {
        productId: 'pro_annual',
        successUrl: 'https://todus.app/mail/inbox?success=true',
      });
    },
  );
});

test('autumn requests surface backend error payloads', async () => {
  await withMockedFetch(
    async () => jsonResponse({ error: 'No customer ID found' }, 401),
    async () => {
      await assert.rejects(
        () => fetchAutumnCustomer('https://api.example.com', 'token-4'),
        /No customer ID found/,
      );
    },
  );
});

test('hasAutumnProAccess supports stripe, products, and unlimited feature fallbacks', () => {
  assert.equal(hasAutumnProAccess(null), false);
  assert.equal(hasAutumnProAccess({ stripe_id: 'cus_123' }), true);
  assert.equal(hasAutumnProAccess({ products: ['pro'] }), true);
  assert.equal(
    hasAutumnProAccess({
      features: {
        'chat-messages': { unlimited: true },
      },
    }),
    true,
  );
  assert.equal(
    hasAutumnProAccess({
      features: {
        'chat-messages': { unlimited: false, balance: 0 },
      },
    }),
    false,
  );
});

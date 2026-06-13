import { afterEach, describe, expect, it, vi } from 'vitest';
vi.mock('cloudflare:workers', () => ({
  env: {},
}));

import { buildDomainCandidates, resolveFaviconUrls, resolveSenderAvatar } from './sender-avatar';

describe('sender-avatar helpers', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('builds progressively broader domain candidates for sender domains', () => {
    expect(buildDomainCandidates('em.stripe.com')).toEqual(['em.stripe.com', 'stripe.com']);
    expect(buildDomainCandidates('mail.anthropic.com')).toEqual([
      'mail.anthropic.com',
      'anthropic.com',
    ]);
  });

  it('extracts icon links from the sender domain homepage before default favicon paths', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(
        '<html><head><link rel="icon" href="/assets/favicon-32x32.png" /></head><body></body></html>',
        {
          status: 200,
          headers: {
            'content-type': 'text/html; charset=utf-8',
          },
        },
      ),
    );

    const urls = await resolveFaviconUrls('stripe.com');

    expect(fetchMock).toHaveBeenCalledWith(
      'https://stripe.com',
      expect.objectContaining({
        redirect: 'follow',
      }),
    );
    expect(urls[0]).toBe('https://stripe.com/assets/favicon-32x32.png');
    expect(urls).toContain('https://stripe.com/favicon.ico');
  });

  it('serves resolveSenderAvatar from the in-memory cache on repeat calls (no googleAuth)', async () => {
    const fetchMock = vi
      .spyOn(globalThis, 'fetch')
      // All third-party lookups fail/404 so resolution is deterministic and fast.
      .mockResolvedValue(new Response('', { status: 404 }));

    // Use a unique domain so the module-level cache isn't pre-populated by another test.
    const email = `someone@cache-test-${Date.now()}.example`;

    const first = await resolveSenderAvatar({ email });
    const callsAfterFirst = fetchMock.mock.calls.length;
    expect(callsAfterFirst).toBeGreaterThan(0);

    const second = await resolveSenderAvatar({ email });
    // Second call must be served from cache — no additional network calls.
    expect(fetchMock.mock.calls.length).toBe(callsAfterFirst);
    expect(second).toEqual(first);
  });
});

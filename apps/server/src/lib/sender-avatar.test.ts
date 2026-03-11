import { afterEach, describe, expect, it, vi } from 'vitest';
vi.mock('cloudflare:workers', () => ({
  env: {},
}));

import { buildDomainCandidates, resolveFaviconUrls } from './sender-avatar';

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
});

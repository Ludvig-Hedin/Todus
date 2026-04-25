import { Hono } from 'hono';
import type { HonoContext } from '../ctx';
import { env } from '../env';
import { refreshSubscriptionCache } from '../lib/billing';

/**
 * Public webhook endpoint for Autumn billing events. Mounted OUTSIDE the /api
 * auth middleware — Autumn calls this server-to-server with no session.
 *
 * Security: HMAC-SHA256 signature verification via AUTUMN_WEBHOOK_SECRET.
 * If the secret is unset (e.g. before the webhook is wired up in the Autumn
 * dashboard) we log a warning and accept — flip to strict-reject once the
 * secret is provisioned in production.
 */

const SIGNATURE_HEADERS = [
  'autumn-signature',
  'x-autumn-signature',
  'webhook-signature',
  'x-webhook-signature',
];

const constantTimeEqual = (a: string, b: string) => {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
};

const hmacSha256Hex = async (secret: string, body: string): Promise<string> => {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(body));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('');
};

const verifySignature = async (
  rawBody: string,
  headers: Headers,
  secret: string | undefined,
): Promise<boolean> => {
  if (!secret) {
    console.warn('[autumn-webhook] AUTUMN_WEBHOOK_SECRET unset — accepting unverified payload');
    return true;
  }
  let header: string | null = null;
  for (const name of SIGNATURE_HEADERS) {
    const v = headers.get(name);
    if (v) {
      header = v;
      break;
    }
  }
  if (!header) {
    console.warn('[autumn-webhook] no signature header found');
    return false;
  }
  // Accept either a bare hex digest or `sha256=<hex>` / `t=...,v1=<hex>` formats.
  const candidates = header
    .split(/[,;]/)
    .map((part) => part.trim().replace(/^(sha256|v1)=/i, ''));
  const expected = await hmacSha256Hex(secret, rawBody);
  return candidates.some((c) => constantTimeEqual(c.toLowerCase(), expected));
};

type AutumnWebhookPayload = {
  type?: string;
  event?: string;
  data?: {
    customer_id?: string;
    customer?: { id?: string };
    user_id?: string;
  };
  customer_id?: string;
};

const extractCustomerId = (payload: AutumnWebhookPayload): string | null => {
  return (
    payload.data?.customer_id ??
    payload.data?.customer?.id ??
    payload.data?.user_id ??
    payload.customer_id ??
    null
  );
};

export const autumnWebhookRouter = new Hono<HonoContext>().post('/', async (c) => {
  const rawBody = await c.req.text();
  const ok = await verifySignature(rawBody, c.req.raw.headers, env.AUTUMN_WEBHOOK_SECRET);
  if (!ok) {
    return c.json({ error: 'invalid signature' }, 401);
  }

  let payload: AutumnWebhookPayload;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return c.json({ error: 'invalid json' }, 400);
  }

  const eventType = payload.type ?? payload.event ?? 'unknown';
  const customerId = extractCustomerId(payload);

  if (!customerId) {
    console.warn('[autumn-webhook] event has no customer id', { eventType });
    return c.json({ ok: true, ignored: 'no_customer_id' });
  }

  // Any state-changing event refreshes our cache from Autumn (the source of
  // truth). We don't try to be clever about which event maps to which fields.
  c.executionCtx?.waitUntil?.(
    refreshSubscriptionCache(customerId).catch((error) => {
      console.error('[autumn-webhook] cache refresh failed', { customerId, eventType, error });
    }),
  );

  return c.json({ ok: true });
});

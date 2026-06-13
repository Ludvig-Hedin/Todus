import { buildPushPayload, type PushSubscription } from '@block65/webcrypto-web-push';
import { eq, inArray } from 'drizzle-orm';
import { pushSubscription } from '../db/schema';
import { createDb } from '../db';
import { env } from '../env';

/**
 * Web Push (RFC 8030/8291) sender for the web app. Cloudflare Workers has no
 * Node `crypto`, so this uses `@block65/webcrypto-web-push` which builds the
 * VAPID JWT and the aes128gcm-encrypted payload with WebCrypto only.
 *
 * Sending is gated behind the VAPID env keys. When they are unset the helpers
 * become a logged no-op so the app runs fine without push configured. Native
 * iOS/macOS use APNs and never touch this path.
 */

/** Notification payload delivered to the service worker (`apps/web/public/sw.js`). */
export type WebPushNotification = {
  title: string;
  body: string;
  /** Relative path the SW navigates to on click (e.g. `/mail/tasks`). */
  url?: string;
  /** Collapse key — a later notification with the same tag replaces the prior one. */
  tag?: string;
  icon?: string;
  badge?: string;
};

type StoredSubscription = {
  id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
  expirationTime: number | null;
};

export function getVapidKeys() {
  const publicKey = env.VAPID_PUBLIC_KEY?.trim();
  const privateKey = env.VAPID_PRIVATE_KEY?.trim();
  if (!publicKey || !privateKey) return null;
  return {
    subject: env.VAPID_SUBJECT?.trim() || 'mailto:ludvig@ludvighedin.com',
    publicKey,
    privateKey,
  };
}

export function isPushConfigured() {
  return getVapidKeys() !== null;
}

/**
 * Sends a notification to one stored subscription. Returns `'gone'` when the
 * push service reports the subscription is dead (404/410) so the caller can
 * prune it. Network/other errors are logged and reported as `'error'`.
 */
async function sendToSubscription(
  sub: StoredSubscription,
  notification: WebPushNotification,
  vapid: NonNullable<ReturnType<typeof getVapidKeys>>,
): Promise<'sent' | 'gone' | 'error'> {
  const subscription: PushSubscription = {
    endpoint: sub.endpoint,
    expirationTime: sub.expirationTime ?? null,
    keys: { p256dh: sub.p256dh, auth: sub.auth },
  };

  try {
    const payload = await buildPushPayload(
      { data: notification, options: { ttl: 60 * 60 * 24, urgency: 'normal' } },
      subscription,
      vapid,
    );

    const res = await fetch(sub.endpoint, {
      method: payload.method,
      headers: payload.headers,
      body: payload.body,
    });

    if (res.ok) return 'sent';
    if (res.status === 404 || res.status === 410) return 'gone';

    const text = await res.text().catch(() => '');
    console.error('[push] push service rejected notification', {
      status: res.status,
      endpoint: sub.endpoint.slice(0, 60),
      body: text.slice(0, 200),
    });
    return 'error';
  } catch (error) {
    console.error('[push] failed to build/send payload', {
      endpoint: sub.endpoint.slice(0, 60),
      error: error instanceof Error ? error.message : String(error),
    });
    return 'error';
  }
}

/**
 * Sends a notification to every web push subscription owned by `userId`.
 * No-ops (and logs) when VAPID keys are unset. Dead subscriptions are deleted.
 */
export async function sendPushToUser(
  userId: string,
  notification: WebPushNotification,
): Promise<{ sent: number; pruned: number; failed: number; skipped: boolean }> {
  const vapid = getVapidKeys();
  if (!vapid) {
    console.warn('[push] VAPID keys not configured — skipping push send', {
      userId,
      title: notification.title,
    });
    return { sent: 0, pruned: 0, failed: 0, skipped: true };
  }

  const { db, conn } = createDb(env.HYPERDRIVE.connectionString);
  try {
    const subs = await db
      .select({
        id: pushSubscription.id,
        endpoint: pushSubscription.endpoint,
        p256dh: pushSubscription.p256dh,
        auth: pushSubscription.auth,
        expirationTime: pushSubscription.expirationTime,
      })
      .from(pushSubscription)
      .where(eq(pushSubscription.userId, userId));

    if (subs.length === 0) {
      return { sent: 0, pruned: 0, failed: 0, skipped: false };
    }

    const results = await Promise.all(
      subs.map((sub) => sendToSubscription(sub, notification, vapid)),
    );

    const goneIds = subs.filter((_, i) => results[i] === 'gone').map((s) => s.id);
    if (goneIds.length > 0) {
      await db.delete(pushSubscription).where(inArray(pushSubscription.id, goneIds));
    }

    return {
      sent: results.filter((r) => r === 'sent').length,
      pruned: goneIds.length,
      failed: results.filter((r) => r === 'error').length,
      skipped: false,
    };
  } finally {
    await conn.end();
  }
}

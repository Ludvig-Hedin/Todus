import { and, desc, eq } from 'drizzle-orm';
import { privateProcedure, router } from '../trpc';
import { pushSubscription } from '../../db/schema';
import { isPushConfigured, sendPushToUser } from '../../lib/push';
import { createDb } from '../../db';
import { env } from '../../env';
import { z } from 'zod';

const getDb = () => createDb(env.HYPERDRIVE.connectionString);

const subscriptionInput = z.object({
  endpoint: z.string().url(),
  keys: z.object({
    p256dh: z.string().min(1),
    auth: z.string().min(1),
  }),
  expirationTime: z.number().nullish(),
});

export const pushRouter = router({
  /**
   * Public VAPID key the browser needs for `PushManager.subscribe()`, plus a
   * `configured` flag so the UI can disable the toggle when push isn't set up.
   */
  getPublicKey: privateProcedure.query(() => {
    const publicKey =
      env.VITE_PUBLIC_VAPID_PUBLIC_KEY?.trim() || env.VAPID_PUBLIC_KEY?.trim() || null;
    return { publicKey, configured: isPushConfigured() && !!publicKey };
  }),

  /** Upsert a browser push subscription, keyed by its unique endpoint. */
  subscribe: privateProcedure.input(subscriptionInput).mutation(async ({ ctx, input }) => {
    const userAgent = ctx.c.req.raw.headers.get('user-agent');
    const now = new Date();
    const { db, conn } = getDb();
    try {
      await db
        .insert(pushSubscription)
        .values({
          id: crypto.randomUUID(),
          userId: ctx.sessionUser.id,
          endpoint: input.endpoint,
          p256dh: input.keys.p256dh,
          auth: input.keys.auth,
          expirationTime: input.expirationTime ?? null,
          userAgent,
          createdAt: now,
          updatedAt: now,
        })
        .onConflictDoUpdate({
          target: pushSubscription.endpoint,
          set: {
            // Re-claim the endpoint for the current user (e.g. shared device)
            // and refresh the keys, which rotate when the UA re-subscribes.
            userId: ctx.sessionUser.id,
            p256dh: input.keys.p256dh,
            auth: input.keys.auth,
            expirationTime: input.expirationTime ?? null,
            userAgent,
            updatedAt: now,
          },
        });
      return { success: true };
    } finally {
      await conn.end();
    }
  }),

  /** Remove a subscription (on unsubscribe / permission revoke). */
  unsubscribe: privateProcedure
    .input(z.object({ endpoint: z.string().url() }))
    .mutation(async ({ ctx, input }) => {
      const { db, conn } = getDb();
      try {
        const deleted = await db
          .delete(pushSubscription)
          .where(
            and(
              eq(pushSubscription.endpoint, input.endpoint),
              eq(pushSubscription.userId, ctx.sessionUser.id),
            ),
          )
          .returning({ id: pushSubscription.id });
        return { success: deleted.length > 0 };
      } finally {
        await conn.end();
      }
    }),

  /** List the current user's subscriptions (for a future device list). */
  listMine: privateProcedure.query(async ({ ctx }) => {
    const { db, conn } = getDb();
    try {
      const rows = await db
        .select({
          id: pushSubscription.id,
          endpoint: pushSubscription.endpoint,
          userAgent: pushSubscription.userAgent,
          createdAt: pushSubscription.createdAt,
        })
        .from(pushSubscription)
        .where(eq(pushSubscription.userId, ctx.sessionUser.id))
        .orderBy(desc(pushSubscription.createdAt));
      return { subscriptions: rows };
    } finally {
      await conn.end();
    }
  }),

  /** Fire a test notification to all of the user's subscriptions. */
  sendTest: privateProcedure.mutation(async ({ ctx }) => {
    const result = await sendPushToUser(ctx.sessionUser.id, {
      title: 'Todus notifications are on',
      body: 'This is a test push. You will get reminders for tasks and events here.',
      url: '/settings/notifications',
      tag: 'todus-test',
    });
    return result;
  }),
});

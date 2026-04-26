import { getCachedSubscription, refreshSubscriptionCache } from '../../lib/billing';
import { privateProcedure, publicProcedure, router } from '../trpc';
import { Autumn, fetchPricingTable } from 'autumn-js';
import { TRPCError } from '@trpc/server';
import { env } from '../../env';
import { z } from 'zod';

const autumn = () => new Autumn({ secretKey: env.AUTUMN_SECRET_KEY });

export const subscriptionRouter = router({
  /**
   * Cached read of current plan + AI usage. Used by every client (web/iOS/macOS)
   * to render plan UI without an Autumn round-trip per request.
   *
   * Self-heals legacy users: if cache shows limit=0 (never hydrated, e.g. user
   * signed up before billing existed) we synchronously call refreshSubscriptionCache
   * which lazy-creates the Autumn customer + attaches `free`. One slow call, then
   * fast forever.
   */
  getStatus: privateProcedure.query(async ({ ctx }) => {
    let sub = await getCachedSubscription(ctx.sessionUser.id);
    if (!sub.aiUsageUnlimited && sub.aiUsageLimit === 0) {
      sub = await refreshSubscriptionCache(ctx.sessionUser.id, {
        name: ctx.sessionUser.name,
        email: ctx.sessionUser.email,
      });
    }
    return {
      plan: sub.plan,
      status: sub.subscriptionStatus,
      aiUsage: {
        used: sub.aiUsageUsed,
        limit: sub.aiUsageLimit,
        remaining: sub.aiUsageRemaining,
        unlimited: sub.aiUsageUnlimited,
        resetAt: sub.aiUsageResetAt ? sub.aiUsageResetAt.toISOString() : null,
      },
    };
  }),

  /** Force-refresh from Autumn — useful right after attach/cancel completes. */
  refresh: privateProcedure.mutation(async ({ ctx }) => {
    const sub = await refreshSubscriptionCache(ctx.sessionUser.id, {
      name: ctx.sessionUser.name,
      email: ctx.sessionUser.email,
    });
    return {
      plan: sub.plan,
      status: sub.subscriptionStatus,
      aiUsage: {
        used: sub.aiUsageUsed,
        limit: sub.aiUsageLimit,
        remaining: sub.aiUsageRemaining,
        unlimited: sub.aiUsageUnlimited,
        resetAt: sub.aiUsageResetAt ? sub.aiUsageResetAt.toISOString() : null,
      },
    };
  }),

  /** Public — visible on the marketing pricing page even when signed out. */
  getPricingTable: publicProcedure.query(async ({ ctx }) => {
    const data = await fetchPricingTable({
      instance: autumn(),
      params: { customer_id: ctx.sessionUser?.id ?? undefined },
    });
    return data.data ?? null;
  }),

  /**
   * Start an upgrade flow. Returns either a Stripe Checkout URL (paid plan,
   * first-time) or a success marker (free plan / already on this product).
   * Mobile clients open the checkout URL in Safari.
   */
  attach: privateProcedure
    .input(z.object({ productId: z.string(), successUrl: z.string().url().optional() }))
    .mutation(async ({ ctx, input }) => {
      const result = await autumn().attach({
        customer_id: ctx.sessionUser.id,
        product_id: input.productId,
        customer_data: {
          name: ctx.sessionUser.name,
          email: ctx.sessionUser.email,
        },
        ...(input.successUrl ? { success_url: input.successUrl } : {}),
      });
      if (!result.data) {
        throw new TRPCError({
          code: 'BAD_REQUEST',
          message: result.error?.message ?? 'Failed to start subscription checkout',
        });
      }
      const data = result.data;
      // Eagerly refresh cache for free plans (no Stripe checkout step).
      if (!data?.checkout_url) {
        await refreshSubscriptionCache(ctx.sessionUser.id, {
          name: ctx.sessionUser.name,
          email: ctx.sessionUser.email,
        });
      }
      return {
        checkoutUrl: data?.checkout_url ?? null,
        productIds: data?.product_ids ?? [],
        message: data?.message ?? '',
      };
    }),

  cancel: privateProcedure
    .input(z.object({ productId: z.string() }))
    .mutation(async ({ ctx, input }) => {
      const result = await autumn().cancel({
        customer_id: ctx.sessionUser.id,
        product_id: input.productId,
      });
      if (!result.data) {
        throw new TRPCError({
          code: 'BAD_REQUEST',
          message: result.error?.message ?? 'Failed to cancel subscription',
        });
      }
      const sub = await refreshSubscriptionCache(ctx.sessionUser.id, {
        name: ctx.sessionUser.name,
        email: ctx.sessionUser.email,
      });
      return {
        plan: sub.plan,
        status: sub.subscriptionStatus,
      };
    }),

  /** Returns a one-shot URL to Autumn's hosted billing portal. */
  getBillingPortalUrl: privateProcedure
    .input(z.object({ returnUrl: z.string().url().optional() }).optional())
    .mutation(async ({ ctx, input }) => {
      const result = await autumn().customers.billingPortal(ctx.sessionUser.id, {
        return_url: input?.returnUrl ?? env.VITE_PUBLIC_APP_URL,
      });
      if (!result.data) {
        throw new TRPCError({
          code: 'BAD_REQUEST',
          message: result.error?.message ?? 'Failed to open billing portal',
        });
      }
      return { url: result.data?.url ?? null };
    }),
});

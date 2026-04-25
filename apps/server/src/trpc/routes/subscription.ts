import { Autumn, fetchPricingTable } from 'autumn-js';
import { z } from 'zod';
import { env } from '../../env';
import { getCachedSubscription, refreshSubscriptionCache } from '../../lib/billing';
import { privateProcedure, publicProcedure, router } from '../trpc';

const autumn = () => new Autumn({ secretKey: env.AUTUMN_SECRET_KEY });

export const subscriptionRouter = router({
  /**
   * Cached read of current plan + AI usage. Used by every client (web/iOS/macOS)
   * to render plan UI without an Autumn round-trip per request.
   */
  getStatus: privateProcedure.query(async ({ ctx }) => {
    const sub = await getCachedSubscription(ctx.sessionUser.id);
    return {
      plan: sub.plan,
      status: sub.subscriptionStatus,
      aiUsage: {
        used: sub.aiUsageUsed,
        limit: sub.aiUsageLimit,
        remaining: sub.aiUsageRemaining,
        resetAt: sub.aiUsageResetAt ? sub.aiUsageResetAt.toISOString() : null,
      },
    };
  }),

  /** Force-refresh from Autumn — useful right after attach/cancel completes. */
  refresh: privateProcedure.mutation(async ({ ctx }) => {
    const sub = await refreshSubscriptionCache(ctx.sessionUser.id);
    return {
      plan: sub.plan,
      status: sub.subscriptionStatus,
      aiUsage: {
        used: sub.aiUsageUsed,
        limit: sub.aiUsageLimit,
        remaining: sub.aiUsageRemaining,
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
      const data = result.data;
      // Eagerly refresh cache for free plans (no Stripe checkout step).
      if (!data?.checkout_url) {
        await refreshSubscriptionCache(ctx.sessionUser.id);
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
      await autumn().cancel({
        customer_id: ctx.sessionUser.id,
        product_id: input.productId,
      });
      const sub = await refreshSubscriptionCache(ctx.sessionUser.id);
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
      return { url: result.data?.url ?? null };
    }),
});

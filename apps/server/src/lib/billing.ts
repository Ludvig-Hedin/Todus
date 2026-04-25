import { Autumn } from 'autumn-js';
import { eq } from 'drizzle-orm';
import { createDb } from '../db';
import { user as userTable } from '../db/schema';
import { env } from '../env';
import { calculateAICostUsd, usdToCredits } from './ai/model-pricing';

export type CachedSubscription = {
  plan: string;
  subscriptionStatus: string;
  aiUsageUsed: number;
  aiUsageLimit: number;
  aiUsageResetAt: Date | null;
  aiUsageRemaining: number;
};

export const PRO_PRODUCT_IDS = ['pro_monthly', 'pro_annual'] as const;

const planFromProductIds = (productIds: string[] | undefined): string => {
  if (!productIds || productIds.length === 0) return 'free';
  if (productIds.some((id) => id === 'pro_annual' || id === 'pro_monthly')) return 'pro';
  if (productIds.some((id) => id.includes('enterprise'))) return 'enterprise';
  if (productIds.some((id) => id.includes('team'))) return 'team';
  return productIds[0] || 'free';
};

const autumnClient = () => new Autumn({ secretKey: env.AUTUMN_SECRET_KEY });

/**
 * Read the user's cached subscription state. If the cache is empty
 * (legacy users created before billing existed), defaults to a free plan
 * with zero usage. Source of truth is Autumn — this is for fast reads only.
 */
export const getCachedSubscription = async (userId: string): Promise<CachedSubscription> => {
  const { db } = createDb(env.HYPERDRIVE.connectionString);
  const rows = await db
    .select({
      plan: userTable.plan,
      subscriptionStatus: userTable.subscriptionStatus,
      aiUsageUsed: userTable.aiUsageUsed,
      aiUsageLimit: userTable.aiUsageLimit,
      aiUsageResetAt: userTable.aiUsageResetAt,
    })
    .from(userTable)
    .where(eq(userTable.id, userId))
    .limit(1);

  const row = rows[0];
  if (!row) {
    return {
      plan: 'free',
      subscriptionStatus: 'active',
      aiUsageUsed: 0,
      aiUsageLimit: 0,
      aiUsageResetAt: null,
      aiUsageRemaining: 0,
    };
  }
  const remaining = Math.max(0, (row.aiUsageLimit ?? 0) - (row.aiUsageUsed ?? 0));
  return {
    plan: row.plan ?? 'free',
    subscriptionStatus: row.subscriptionStatus ?? 'active',
    aiUsageUsed: row.aiUsageUsed ?? 0,
    aiUsageLimit: row.aiUsageLimit ?? 0,
    aiUsageResetAt: row.aiUsageResetAt ?? null,
    aiUsageRemaining: remaining,
  };
};

/**
 * Hydrate the cache from Autumn (called after attach/cancel/webhook events).
 * Returns the new cached state. Failures log and return current cache.
 */
export const refreshSubscriptionCache = async (
  userId: string,
): Promise<CachedSubscription> => {
  try {
    const { data: customer } = await autumnClient().customers.get(userId);
    if (!customer) return getCachedSubscription(userId);

    const productIds = (customer.products ?? []).map((p) => p.id).filter(Boolean) as string[];
    const plan = planFromProductIds(productIds);
    const aiUsageFeature = (customer as any).features?.ai_usage;
    const limit = Number(aiUsageFeature?.included_usage ?? 0);
    const balance = Number(aiUsageFeature?.balance ?? limit);
    const used = Math.max(0, limit - balance);
    const resetAt = aiUsageFeature?.next_reset_at
      ? new Date(Number(aiUsageFeature.next_reset_at))
      : null;
    const status =
      (customer.products ?? []).find((p) => p.status)?.status ?? 'active';

    const { db } = createDb(env.HYPERDRIVE.connectionString);
    await db
      .update(userTable)
      .set({
        plan,
        subscriptionStatus: status,
        aiUsageUsed: used,
        aiUsageLimit: limit,
        aiUsageResetAt: resetAt,
        updatedAt: new Date(),
      })
      .where(eq(userTable.id, userId));

    return {
      plan,
      subscriptionStatus: status,
      aiUsageUsed: used,
      aiUsageLimit: limit,
      aiUsageResetAt: resetAt,
      aiUsageRemaining: Math.max(0, limit - used),
    };
  } catch (error) {
    console.error('[billing] refreshSubscriptionCache failed', error);
    return getCachedSubscription(userId);
  }
};

/**
 * Pre-flight check before an AI call — returns true if the user has any
 * remaining credits. Cached read; ~1ms vs 200ms for an Autumn round-trip.
 */
export const hasAiCredits = async (userId: string): Promise<boolean> => {
  const sub = await getCachedSubscription(userId);
  return sub.aiUsageLimit === 0 || sub.aiUsageRemaining > 0;
};

/**
 * Track real AI cost after a model call. Computes USD from token counts,
 * pushes to Autumn (source of truth), and updates the local cache.
 * Always wrapped — tracking failures must never affect the user response.
 */
export const trackAiUsage = async (params: {
  userId: string;
  model: string;
  inputTokens: number;
  outputTokens: number;
  idempotencyKey?: string;
}): Promise<void> => {
  const { userId, model, inputTokens, outputTokens, idempotencyKey } = params;
  const usd = calculateAICostUsd(model, inputTokens, outputTokens);
  const credits = usdToCredits(usd);
  if (credits <= 0) return;

  try {
    await autumnClient().track({
      customer_id: userId,
      feature_id: 'ai_usage',
      value: credits,
      ...(idempotencyKey ? { idempotency_key: idempotencyKey } : {}),
    });
  } catch (error) {
    console.error('[billing] Autumn track failed', error);
  }

  try {
    const { db } = createDb(env.HYPERDRIVE.connectionString);
    const sub = await getCachedSubscription(userId);
    await db
      .update(userTable)
      .set({
        aiUsageUsed: sub.aiUsageUsed + credits,
        updatedAt: new Date(),
      })
      .where(eq(userTable.id, userId));
  } catch (error) {
    console.error('[billing] cache usage update failed', error);
  }
};

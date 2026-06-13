import { calculateAICostUsd, usdToCredits } from './ai/model-pricing';
import { user as userTable } from '../db/schema';
import { Autumn } from 'autumn-js';
import { eq } from 'drizzle-orm';
import { createDb } from '../db';
import { env } from '../env';

export type CachedSubscription = {
  plan: string;
  subscriptionStatus: string;
  aiUsageUsed: number;
  aiUsageLimit: number;
  aiUsageResetAt: Date | null;
  aiUsageRemaining: number;
  aiUsageUnlimited: boolean;
};

export const PRO_PRODUCT_IDS = ['pro_monthly', 'pro_annual'] as const;
const UNLIMITED_AI_USAGE_SENTINEL = -1;

const planFromProductIds = (productIds: string[] | undefined): string => {
  if (!productIds || productIds.length === 0) return 'free';
  if (productIds.some((id) => id === 'pro_annual' || id === 'pro_monthly')) return 'pro';
  if (productIds.some((id) => id.includes('enterprise'))) return 'enterprise';
  if (productIds.some((id) => id.includes('team'))) return 'team';
  return productIds[0] || 'free';
};

const autumnClient = () => new Autumn({ secretKey: env.AUTUMN_SECRET_KEY });

type AutumnResult<T> = Awaited<ReturnType<Autumn['customers']['get']>> & {
  data: T | null;
};

const isAutumnNotFound = (result: {
  error: { code?: string; message?: string } | null;
  statusCode?: number;
}) =>
  result.statusCode === 404 ||
  result.error?.code === 'not_found' ||
  /not found/i.test(result.error?.message ?? '');

const logAutumnFailure = (
  label: string,
  result: { error: { code?: string; message?: string } | null; statusCode?: number },
) => {
  console.error(`[billing] ${label} failed`, {
    statusCode: result.statusCode ?? null,
    code: result.error?.code ?? null,
    message: result.error?.message ?? null,
  });
};

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
      aiUsageUnlimited: false,
    };
  }
  const unlimited = (row.aiUsageLimit ?? 0) < 0;
  const remaining = unlimited ? 0 : Math.max(0, (row.aiUsageLimit ?? 0) - (row.aiUsageUsed ?? 0));
  return {
    plan: row.plan ?? 'free',
    subscriptionStatus: row.subscriptionStatus ?? 'active',
    aiUsageUsed: row.aiUsageUsed ?? 0,
    aiUsageLimit: unlimited ? 0 : (row.aiUsageLimit ?? 0),
    aiUsageResetAt: row.aiUsageResetAt ?? null,
    aiUsageRemaining: remaining,
    aiUsageUnlimited: unlimited,
  };
};

export type ActiveProduct = {
  /** The Autumn product id the user should cancel/manage (e.g. `pro_annual`). */
  productId: string | null;
  /** Billing interval derived from the product id, when determinable. */
  interval: 'monthly' | 'annual' | null;
  /** Product status as reported by Autumn (`active` / `trialing` / `scheduled`). */
  status: string | null;
};

const intervalFromProductId = (productId: string | null): ActiveProduct['interval'] => {
  if (!productId) return null;
  if (/annual|year/i.test(productId)) return 'annual';
  if (/month/i.test(productId)) return 'monthly';
  return null;
};

/**
 * Resolve the user's *active* paid product directly from Autumn (source of truth).
 *
 * The local DB cache only stores a coarse `plan` ("free"/"pro"/…) — it does NOT
 * distinguish `pro_monthly` from `pro_annual`, so clients can't tell which product
 * to cancel from the cached read alone. This does the authoritative lookup.
 *
 * Skips paid (non-free) products that are already canceled/expired so the returned
 * id is genuinely cancellable. Free users return the `free` product id. Failures
 * fail soft (return nulls) — surfacing product metadata must never break getStatus.
 */
export const getActiveProduct = async (userId: string): Promise<ActiveProduct> => {
  try {
    const result = await autumnClient().customers.get(userId);
    const products = result.data?.products ?? [];
    if (products.length === 0) return { productId: null, interval: null, status: null };

    // Prefer a live paid product (not expired, not canceled). Free is the fallback.
    // Compare status via String() so a string-enum value matches the literal at
    // runtime without a TS enum-vs-literal comparison error.
    const paid = products.filter((p) => p.id && p.id !== 'free');
    const statusOf = (p: { status: unknown }) => String(p.status);
    const live =
      paid.find((p) => statusOf(p) === 'active' || statusOf(p) === 'trialing') ??
      paid.find((p) => statusOf(p) === 'scheduled' && !p.canceled_at) ??
      paid[0] ??
      products.find((p) => p.id === 'free') ??
      products[0];

    const productId = live?.id ?? null;
    return {
      productId,
      interval: intervalFromProductId(productId),
      status: live?.status ? String(live.status) : null,
    };
  } catch (error) {
    console.error('[billing] getActiveProduct failed (failing soft)', error);
    return { productId: null, interval: null, status: null };
  }
};

/**
 * Hydrate the cache from Autumn (called after attach/cancel/webhook events).
 * If no Autumn customer exists yet (legacy user from before billing existed,
 * or Autumn was down during signup) this lazily creates one and attaches the
 * `free` product so the user immediately gets their default credits. Returns
 * the new cached state. Failures log and return whatever cache exists.
 */
export const refreshSubscriptionCache = async (
  userId: string,
  ensureCustomerData?: { name?: string; email?: string },
): Promise<CachedSubscription> => {
  try {
    const autumn = autumnClient();
    let customerResult: AutumnResult<
      Awaited<ReturnType<typeof autumn.customers.get>>['data']
    > | null = null;
    try {
      customerResult = await autumn.customers.get(userId);
    } catch (error) {
      console.error('[billing] customers.get failed', error);
      return getCachedSubscription(userId);
    }
    let customer = customerResult.data;

    // Lazy-create the Autumn customer + free plan if missing. Idempotent — Autumn
    // returns the existing customer on duplicate id. Only do this on a confirmed
    // not-found result; transient API failures must not mutate billing state.
    if (!customer) {
      if (!isAutumnNotFound(customerResult)) {
        logAutumnFailure('customers.get', customerResult);
        return getCachedSubscription(userId);
      }

      try {
        const createResult = await autumn.customers.create({
          id: userId,
          name: ensureCustomerData?.name ?? null,
          email: ensureCustomerData?.email ?? null,
        });
        if (!createResult.data && !isAutumnNotFound(createResult)) {
          logAutumnFailure('lazy customers.create', createResult);
        }
      } catch (error) {
        console.error('[billing] lazy customers.create failed', error);
      }

      try {
        const attachResult = await autumn.attach({ customer_id: userId, product_id: 'free' });
        if (!attachResult.data && !isAutumnNotFound(attachResult)) {
          logAutumnFailure('lazy attach free', attachResult);
        }
      } catch (error) {
        console.error('[billing] lazy attach free failed', error);
      }

      try {
        customerResult = await autumn.customers.get(userId);
        customer = customerResult.data;
      } catch (error) {
        console.error('[billing] customers.get after lazy create failed', error);
        return getCachedSubscription(userId);
      }
      if (!customer) {
        if (!isAutumnNotFound(customerResult)) {
          logAutumnFailure('customers.get after lazy create', customerResult);
        }
        return getCachedSubscription(userId);
      }
    }

    const productIds = (customer.products ?? []).map((p) => p.id).filter(Boolean) as string[];
    const plan = planFromProductIds(productIds);
    const aiUsageFeature = customer.features?.['ai_usage'];
    // Strict equality: Autumn has historically sent `"true"` / `"false"` strings on some
    // payloads. `Boolean("false")` is `true`, which would silently grant unlimited AI.
    const unlimited = aiUsageFeature?.unlimited === true;
    const limit = unlimited ? 0 : Number(aiUsageFeature?.included_usage ?? 0);
    const balance = unlimited ? 0 : Number(aiUsageFeature?.balance ?? limit);
    const used = unlimited ? Number(aiUsageFeature?.usage ?? 0) : Math.max(0, limit - balance);
    const resetAt = aiUsageFeature?.next_reset_at
      ? new Date(Number(aiUsageFeature.next_reset_at))
      : null;
    const status = (customer.products ?? []).find((p) => p.status)?.status ?? 'active';

    // If Autumn's free product has no ai_usage feature (or included_usage=0), it means the
    // product isn't fully configured yet. Apply a default budget so legacy/free users aren't
    // permanently locked out. Once Autumn returns a real value, that wins on next refresh.
    const FREE_PLAN_DEFAULT_AI_CREDITS = 1.0;
    const effectiveLimit =
      !unlimited && plan === 'free' && limit === 0 ? FREE_PLAN_DEFAULT_AI_CREDITS : limit;

    const { db } = createDb(env.HYPERDRIVE.connectionString);
    await db
      .update(userTable)
      .set({
        plan,
        subscriptionStatus: status,
        aiUsageUsed: used,
        aiUsageLimit: unlimited ? UNLIMITED_AI_USAGE_SENTINEL : effectiveLimit,
        aiUsageResetAt: resetAt,
        updatedAt: new Date(),
      })
      .where(eq(userTable.id, userId));

    return {
      plan,
      subscriptionStatus: status,
      aiUsageUsed: used,
      aiUsageLimit: effectiveLimit,
      aiUsageResetAt: resetAt,
      aiUsageRemaining: unlimited ? 0 : Math.max(0, effectiveLimit - used),
      aiUsageUnlimited: unlimited,
    };
  } catch (error) {
    console.error('[billing] refreshSubscriptionCache failed', error);
    return getCachedSubscription(userId);
  }
};

/**
 * Pre-flight check before an AI call — returns true if the user has any
 * remaining credits.
 *
 * Fast path: serve from local DB cache (~1ms). If the cache shows 0 credits
 * (either never hydrated or genuinely exhausted), fall back to autumn.check()
 * which is the authoritative source. Fails open on Autumn errors so a billing
 * hiccup never blocks the user.
 */
export const hasAiCredits = async (userId: string): Promise<boolean> => {
  const sub = await getCachedSubscription(userId);
  if (sub.aiUsageUnlimited) return true;
  if (sub.aiUsageRemaining > 0) return true;

  // Cache shows no credits — ask Autumn directly. This handles: first-time users
  // whose cache was never populated, plan changes that haven't synced yet, and
  // cases where the cached balance is stale. Autumn lazy-creates the customer
  // and attaches the free plan if needed.
  try {
    const result = await autumnClient().check({
      customer_id: userId,
      feature_id: 'ai_usage',
      customer_data: {},
    });
    if (result.data) {
      return result.data.allowed;
    }
    console.error('[billing] hasAiCredits autumn.check returned no data', { userId });
    return true; // fail open
  } catch (error) {
    console.error('[billing] hasAiCredits autumn.check failed (failing open)', error);
    return true; // fail open — billing hiccup must not block AI
  }
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
  await trackCreditsUsed({ userId, credits: usdToCredits(usd), idempotencyKey });
};

/**
 * Generic credit-debit helper for AI surfaces that price by something other
 * than tokens (voice = per-minute, image = per-image, etc.). Caller computes
 * the credit value; we just push to Autumn + update the cache.
 */
export const trackCreditsUsed = async (params: {
  userId: string;
  credits: number;
  idempotencyKey?: string;
}): Promise<void> => {
  const { userId, credits, idempotencyKey } = params;
  if (!credits || credits <= 0) return;

  try {
    const result = await autumnClient().track({
      customer_id: userId,
      feature_id: 'ai_usage',
      value: credits,
      ...(idempotencyKey ? { idempotency_key: idempotencyKey } : {}),
    });
    if (!result.data) {
      logAutumnFailure('Autumn track', result);
      return;
    }
  } catch (error) {
    console.error('[billing] Autumn track failed', error);
    return;
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

/**
 * Convert a Gemini Live voice session duration to credits.
 * Estimate: ~$0.10/minute (audio in/out at Gemini Live Tier 1 typical mix).
 * Cheap rounding to whole seconds — voice sessions vary too much for
 * sub-second precision to matter.
 */
export const voiceSessionCostCredits = (durationMs: number): number => {
  const minutes = Math.max(0, durationMs / 60_000);
  return usdToCredits(minutes * 0.1);
};

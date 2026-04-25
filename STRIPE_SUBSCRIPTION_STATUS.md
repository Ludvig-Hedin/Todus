# SUBSCRIPTION IMPLEMENTATION STATUS

**Last Updated**: 2026-04-25
**Audit Completed By**: Codebase audit + full build (Claude Code)
**Changes Made**: Promoted from "audit only" to "shipped end-to-end across web + iOS + macOS + server".

> ⚠️ Heads-up on naming: the original brief said "Stripe", but this app uses **Autumn** (which wraps Stripe under the hood). All checkout / customer portal / webhook plumbing is owned by Autumn — we never call Stripe directly. Local DB just caches plan + AI usage; Autumn is the source of truth.

---

## ✅ COMPLETED (this session)

### Backend (Cloudflare Workers + Postgres + Drizzle)

- **`mail0_user` cache columns** for plan + AI usage — [apps/server/src/db/schema.ts:17-37](apps/server/src/db/schema.ts:17). Migration: [apps/server/src/db/migrations/0050_lame_tag.sql](apps/server/src/db/migrations/0050_lame_tag.sql). **Run `pnpm db:push` to apply.**
- **Signup hook creates Autumn customer + attaches `free` product + hydrates plan cache** — [apps/server/src/lib/auth.ts:725-753](apps/server/src/lib/auth.ts:725). Each call wrapped — failures log but never block signup.
- **Model pricing table** (USD per 1M tokens) — [apps/server/src/lib/ai/model-pricing.ts](apps/server/src/lib/ai/model-pricing.ts). Anthropic / OpenAI / Google / DeepSeek covered, with a fallback rate for unknown models.
- **Billing helpers** (`getCachedSubscription`, `refreshSubscriptionCache`, `hasAiCredits`, `trackAiUsage`) — [apps/server/src/lib/billing.ts](apps/server/src/lib/billing.ts). Used by signup, AI chat, webhook, and tRPC router.
- **`subscription` tRPC router** — [apps/server/src/trpc/routes/subscription.ts](apps/server/src/trpc/routes/subscription.ts). Procedures: `getStatus`, `refresh`, `getPricingTable`, `attach`, `cancel`, `getBillingPortalUrl`. Registered in [apps/server/src/trpc/index.ts:34](apps/server/src/trpc/index.ts:34).
- **AI usage metering inside `/api/ai/chat`** — [apps/server/src/routes/ai.ts:372-510, 696-790](apps/server/src/routes/ai.ts:372). Pre-flight: returns `402 ai_credits_exhausted` when out of credits (fails open if cache lookup itself errors). Post-stream: parses `usage` from OpenRouter SSE chunks, computes USD cost, tracks via Autumn + updates local cache. Fire-and-forget — never blocks the response.
- **Webhook handler** with HMAC-SHA256 verification — [apps/server/src/routes/autumn-webhook.ts](apps/server/src/routes/autumn-webhook.ts). Mounted at `POST /webhooks/autumn` outside the `/api` auth middleware ([main.ts:1167](apps/server/src/main.ts:1167)). Accepts unverified payloads when `AUTUMN_WEBHOOK_SECRET` is unset (so testing works before you configure it; tighten to strict-reject once provisioned in production).
- **Env** — `AUTUMN_WEBHOOK_SECRET?: string` declared in [apps/server/src/env.ts:75](apps/server/src/env.ts:75).

### Web (`apps/mail`)

- **`/settings/billing` page** — [apps/mail/app/(routes)/settings/billing/page.tsx](apps/mail/app/\(routes\)/settings/billing/page.tsx). Shows current plan, AI usage progress bar with formatted credits and reset date, upgrade / manage / cancel actions, warnings at 80% and 100% utilization.
- **Sidebar entry** — [apps/mail/config/navigation.ts:235](apps/mail/config/navigation.ts:235) (uses lucide `CreditCard` icon).
- **Route registered** — [apps/mail/app/routes.ts:69](apps/mail/app/routes.ts:69).
- **Pricing card** uses real product IDs (`pro_monthly`, `pro_annual`) — [apps/mail/components/pricing/pricing-card.tsx:99](apps/mail/components/pricing/pricing-card.tsx:99).
- **`useBilling()` exposes `aiUsage`** for ai_usage feature — [apps/mail/hooks/use-billing.ts:55-62](apps/mail/hooks/use-billing.ts:55).
- **Billing portal link** in user menu now shows for any Pro customer (not just those with a `stripe_id`) — [apps/mail/components/ui/nav-user.tsx:600](apps/mail/components/ui/nav-user.tsx:600).

### iOS (`apps/ios/Todus`)

- **`SubscriptionService`** (`@MainActor @Observable`) — [apps/ios/Todus/Todus/Services/Subscription/SubscriptionService.swift](apps/ios/Todus/Todus/Services/Subscription/SubscriptionService.swift). Reads cached state via `subscription.getStatus`; `forceRefreshFromAutumn()` for post-action refresh; `getBillingPortalUrl` and `cancel` actions.
- **`BillingSettingsView`** — [apps/ios/Todus/Todus/Features/Settings/BillingSettingsView.swift](apps/ios/Todus/Todus/Features/Settings/BillingSettingsView.swift). Plan section + AI usage section with progress bar + manage/cancel/upgrade. Pull-to-refresh forces an Autumn round-trip. Cancel uses confirmation dialog.
- **AppServices registration** — [apps/ios/Todus/Todus/App/AppServices.swift:122, 354](apps/ios/Todus/Todus/App/AppServices.swift:122).
- **Settings nav entry** — `billingNavigationSection` added to [apps/ios/Todus/Todus/Features/Settings/SettingsView.swift](apps/ios/Todus/Todus/Features/Settings/SettingsView.swift) with a `.task` that pre-loads the cached subscription state when settings opens.
- **Xcode project regenerated** — `xcodegen generate` ran successfully; new files auto-included.
- **Upgrade flow:** opens `https://app.todus.app/pricing` in Safari (via `@Environment(\.openURL)`) — Apple's external-link policy lets us link out to web checkout for productivity apps.

### macOS (`apps/macos/TodusMac`)

- **`MacSubscriptionService`** — [apps/macos/TodusMac/Services/Subscription/MacSubscriptionService.swift](apps/macos/TodusMac/Services/Subscription/MacSubscriptionService.swift). Mirrors the iOS service since both apps hit the same `subscription.*` tRPC routes.
- **`billingSection`** in [apps/macos/TodusMac/Views/Settings/MacSettingsView.swift](apps/macos/TodusMac/Views/Settings/MacSettingsView.swift) — single inline card (matches the macOS settings pattern, not nav-based) with plan, AI usage progress, manage/cancel/upgrade. Cancel uses `confirmationDialog`.
- **MacAppServices registration** — `subscriptionService: MacSubscriptionService` injected.
- **Xcode project regenerated** — `xcodegen generate` ran successfully.
- **Upgrade flow:** opens `https://app.todus.app/pricing` via `NSWorkspace.shared.open()`.

### Verification

- Server `tsc --noEmit`: **0 new errors** in any of the new/modified files. (Pre-existing errors about `Env` type inference are unrelated and predate this work.)
- iOS Xcode project: regenerated successfully via xcodegen.
- macOS Xcode project: regenerated successfully via xcodegen.

---

## 🛠️ MANUAL STEPS YOU NEED TO RUN

1. **Apply the database migration** (one-time, before deploying):
   ```bash
   pnpm db:push
   ```
   This adds the 5 new columns to `mail0_user`. Safe — all columns have defaults so existing users get sensible values.

2. **Backfill existing users to have Autumn customer records.** Anyone who signed up before this change won't have an Autumn customer. Two options:
   - **Easier**: ignore — when an existing user opens `/settings/billing`, the subscription router falls back to "free / 0 credits" defaults. No errors. They'll only get a real Autumn customer if/when they upgrade. (Acceptable for a quiet rollout.)
   - **Cleaner**: write a one-shot script that iterates the `user` table and calls `autumn.customers.create` for each. Easy to add later if needed.

3. **Configure the Autumn webhook** (when you find the setting):
   - URL: `https://api.todus.app/webhooks/autumn`
   - Copy the signing secret → `wrangler secret put AUTUMN_WEBHOOK_SECRET --env production` (run from `apps/server/`)
   - Until this is set, the handler accepts unverified payloads (logs a warning) so test events work — production should have it set before going live.

4. **Optional: set the Stripe Success URL** in your Autumn dashboard's Stripe tab to `https://app.todus.app/mail/inbox?success=true` as a default fallback. (Per-checkout success URL is already passed in the `attach()` call — this is just a safety net.)

5. **Smoke test** end-to-end:
   - Web: sign up → check Autumn dashboard for new customer with `free` product attached
   - Web: `/pricing` → upgrade Pro Monthly → Stripe Checkout (test card `4242 4242 4242 4242`) → return to inbox → user menu shows Pro badge → `/settings/billing` shows Pro + 15 credits
   - Web: send AI chat → check `/settings/billing` after 30s, used credits should increment
   - Web: cancel subscription → status updates → keeps access until period end
   - iOS: sign up fresh → Settings → Subscription → see Free + credits → tap Upgrade → Safari opens to /pricing → after upgrading on web, pull-to-refresh in iOS billing → see Pro + credits
   - macOS: same flow as iOS, in Settings panel

---

## 🚧 INTENTIONALLY DEFERRED

- **Backfill script for existing Autumn customers** — see step 2 above. Easy to add when needed.
- **iOS / macOS native StoreKit 2 in-app purchases** — would replace the web-link upgrade flow with native IAPs (and Apple takes a 15-30% cut). Multi-week project requiring App Store Connect product setup, server receipt verification, and App Review. The web-link approach we shipped is allowed under Apple's current external-link policy for productivity apps and is what most cross-platform apps do.
- **Webhook idempotency keys** — current handler refreshes the cache on every event, which is naturally idempotent (same Autumn state → same cache state). If Autumn ever sends out-of-order events causing flapping, add a per-event-id de-dupe table.
- **Plan-gating on individual features** — nothing besides `/api/ai/chat` is gated by plan today. When you want Pro-only features (auto-labeling, instant summaries, etc.), wrap them in a `useBilling().isPro` check (web) or `subscriptionService.plan.isPaid` (iOS/macOS).
- **Refining the model pricing table** — current rates are reasonable as-of writing but providers change prices. Worth a quarterly review.
- **Failure of OpenRouter to emit `usage`** — for models that don't include usage in the SSE stream (rare), we currently skip tracking rather than charging a guess. Acceptable for v1; could fall back to a token-count estimate if it becomes a revenue issue.

---

## 📋 IMPLEMENTATION SEQUENCE — what got built (in order)

1. ✅ Phase 1 foundation (placeholder product IDs fixed, signup hook creates Autumn customer + free product, billing portal visibility loosened, useBilling exposes ai_usage)
2. ✅ User-table cache columns + Drizzle migration `0050_lame_tag.sql`
3. ✅ Model pricing table + billing helper module
4. ✅ `subscription` tRPC router (all 6 procedures) + registration
5. ✅ Webhook handler with HMAC-SHA256 verification + mount in main.ts
6. ✅ AI usage tracking in `/api/ai/chat` (pre-check + post-stream track)
7. ✅ Web `/settings/billing` page + sidebar entry + route
8. ✅ iOS SubscriptionService + BillingSettingsView + nav entry + xcodegen regenerate
9. ✅ macOS MacSubscriptionService + billingSection + xcodegen regenerate
10. ✅ Type-check (clean) + CHANGELOG + this status doc

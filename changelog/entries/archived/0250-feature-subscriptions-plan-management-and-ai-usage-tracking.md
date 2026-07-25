---
id: 0250
title: "Feature — Subscriptions, plan management, and AI usage tracking (web + iOS + macOS + server)"
status: archived
category: Added
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Feature — Subscriptions, plan management, and AI usage tracking (web + iOS + macOS + server)

- [Feature] **Backend:** Autumn-based subscriptions wired end-to-end. New users get an Autumn customer with the `free` product on signup. New `subscription` tRPC router exposes `getStatus` / `refresh` / `attach` / `cancel` / `getBillingPortalUrl` / `getPricingTable`.
- [Feature] **Backend:** `mail0_user` cache columns (`plan`, `subscription_status`, `ai_usage_used`, `ai_usage_limit`, `ai_usage_reset_at`) so plan UI renders without an Autumn round-trip per request. Migration `0050_lame_tag.sql`.
- [Feature] **Backend:** AI usage metering. `/api/ai/chat` now (1) blocks with `402 ai_credits_exhausted` when the user is out of credits, (2) requests OpenRouter `stream_options.include_usage`, (3) parses real token counts from the SSE stream, (4) computes USD cost from a per-model rate table, (5) tracks the cost as `ai_usage` credits in Autumn (1 credit = $1) — fire-and-forget so tracking failures never affect chat.
- [Feature] **Backend:** Public webhook handler at `POST /webhooks/autumn` with HMAC-SHA256 signature verification (`AUTUMN_WEBHOOK_SECRET`). Refreshes the cached subscription state for the affected customer on any Autumn event.
- [Feature] **Web:** New `/settings/billing` page with current plan, AI usage progress bar, manage / upgrade / cancel buttons, and warnings at 80% / 100% utilization. Sidebar entry added.
- [Feature] **Web:** Pricing card now uses real product IDs (`pro_monthly` / `pro_annual`); upgrade flow opens Stripe Checkout via Autumn.
- [Feature] **iOS:** `SubscriptionService` (cached read of plan + AI usage). New `BillingSettingsView` with manage-billing and cancel actions; nav entry added under Settings → Subscription. Free users get an "Upgrade to Pro" link out to the web pricing page (Apple's external-link policy).
- [Feature] **macOS:** `MacSubscriptionService` and a new `billingSection` on `MacSettingsView` mirroring the iOS UI: plan summary, credit progress bar, manage/cancel/upgrade. Opens billing portal via `NSWorkspace`.
- [Files] `apps/server/src/db/schema.ts`, `apps/server/src/lib/billing.ts`, `apps/server/src/lib/ai/model-pricing.ts`, `apps/server/src/trpc/routes/subscription.ts`, `apps/server/src/routes/autumn-webhook.ts`, `apps/server/src/routes/ai.ts`, `apps/server/src/lib/auth.ts`, `apps/server/src/main.ts`, `apps/server/src/env.ts`, `apps/server/src/trpc/index.ts`, `apps/server/src/db/migrations/0050_lame_tag.sql`, `apps/mail/app/(routes)/settings/billing/page.tsx`, `apps/mail/app/routes.ts`, `apps/mail/config/navigation.ts`, `apps/mail/components/pricing/pricing-card.tsx`, `apps/mail/components/ui/nav-user.tsx`, `apps/mail/hooks/use-billing.ts`, `apps/mail/lib/utils.ts`, `apps/ios/Todus/Todus/Services/Subscription/SubscriptionService.swift`, `apps/ios/Todus/Todus/Features/Settings/BillingSettingsView.swift`, `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`, `apps/ios/Todus/Todus/App/AppServices.swift`, `apps/macos/TodusMac/Services/Subscription/MacSubscriptionService.swift`, `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`, `apps/macos/TodusMac/App/MacAppServices.swift`
- [Manual steps required] Run `pnpm db:push` (or `pnpm db:migrate` in prod) to apply migration `0050_lame_tag.sql`. Set `AUTUMN_SECRET_KEY` (already done by user). Once the webhook setting is found in the Autumn dashboard, set `AUTUMN_WEBHOOK_SECRET` via `wrangler secret put` and point Autumn at `https://api.todus.app/webhooks/autumn`.

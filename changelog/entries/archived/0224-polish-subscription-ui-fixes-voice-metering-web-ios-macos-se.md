---
id: 0224
title: "Polish — Subscription UI fixes + voice metering (web + iOS + macOS + server)"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Polish — Subscription UI fixes + voice metering (web + iOS + macOS + server)

- [Feature] **Voice chat AI usage now tracked.** `/api/ai/voice-ws` (Gemini Live proxy) gets a pre-flight credit check + per-session-minute metering on close. Estimate: 0.10 credits/minute (~$0.10/min Gemini Live blended audio rate). Idempotent close handling — both client and upstream close events route through a single `trackVoiceUsage()` flag.
- [Hardening] **Voice chat only starts billing on first billable user input.** Opening the voice sheet and idling no longer consumes credits; the proxy starts metering only after the first client audio/text/media payload. The temporary `/admin/run-migrations` repair route is no longer guarded by a committed token and now stays disabled unless `ADMIN_RUN_MIGRATIONS_TOKEN` is configured as a server secret.
- [Fix] **Legacy users no longer see "No AI credits on the free plan."** `subscription.getStatus` now self-heals: if cache shows `aiUsageLimit=0`, it synchronously calls `refreshSubscriptionCache()` which lazy-creates the Autumn customer + attaches `free`. Idempotent; one slow call, then fast forever. Existing users from before billing existed get hydrated on first settings open.
- [Fix] **Wrong upgrade URL.** iOS + macOS were opening `https://app.todus.app/pricing` (which doesn't exist) — fixed to derive the web host by stripping the `api.` subdomain prefix, with `https://todus.app/pricing` as the fallback root.
- [UX] **No more dollar amounts in the billing UI.** Per the user's call (the credit→USD conversion is internal), removed all `$N` references and "1 credit ≈ $1" footnotes from web, iOS, and macOS billing pages. Plan-includes lists now read "15 credits / month" instead of "$15 of AI usage".
- [UX] **Bigger, cleaner usage card on all three apps.** Headline is now a 5xl tabular-numerals "X / Y left" credits-remaining number, prominent percent-remaining sub, full-width thicker progress bar, used/total tabular footer. Out-of-credits banner has an inline Upgrade button (web) instead of a separate row.
- [Files] `apps/server/src/lib/billing.ts`, `apps/server/src/trpc/routes/subscription.ts`, `apps/server/src/routes/ai.ts`, `apps/mail/app/(routes)/settings/billing/page.tsx`, `apps/ios/Todus/Todus/Features/Settings/BillingSettingsView.swift`, `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`
- [Verified] Server + web `tsc --noEmit`: 0 new errors. Voice metering uses `trackCreditsUsed()` (a new generic credit-debit helper) so future per-minute or per-image AI surfaces can plug in without a token-conversion shim.

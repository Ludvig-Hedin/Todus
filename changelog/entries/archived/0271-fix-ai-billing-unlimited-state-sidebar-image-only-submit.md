---
id: 0271
title: "Fix — AI billing unlimited-state + sidebar image-only submit"
status: archived
category: Fixed
release_date: 2026-04-26
source: CHANGELOG.md
---

## [2026-04-26] Fix — AI billing unlimited-state + sidebar image-only submit

- [Fix] **Server billing:** `refreshSubscriptionCache()` now preserves Autumn `ai_usage.unlimited` in the cached subscription state instead of collapsing it to zero credits. The server stores a negative DB sentinel internally, returns `aiUsage.unlimited` to clients, and keeps `hasAiCredits()` open for unlimited plans across text chat, voice chat, and ZeroAgent chat.
- [Fix] **Web/mail AI sidebar:** image-only pasted submits now go through `append(..., { allowEmptySubmit: true })` instead of the plain `handleSubmit()` path, so attachment-only turns are no longer dropped and the pending image tray is only cleared after a successful send.
- [Fix] **Native + web billing UI:** iOS, macOS, and the mail settings billing page now render unlimited AI usage explicitly as **Unlimited** instead of showing a zero-credit exhausted state.
- [Files] `apps/server/src/lib/billing.ts`, `apps/server/src/trpc/routes/subscription.ts`, `apps/mail/components/create/ai-chat.tsx`, `apps/mail/app/(routes)/settings/billing/page.tsx`, `apps/ios/Todus/Todus/Services/Subscription/SubscriptionService.swift`, `apps/ios/Todus/Todus/Features/Settings/BillingSettingsView.swift`, `apps/macos/TodusMac/Services/Subscription/MacSubscriptionService.swift`, `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`, `CHANGELOG.md`, `TASK.md`

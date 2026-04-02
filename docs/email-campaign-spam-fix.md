## Email campaign deduplication

Date: 2026-04-02

### User-facing issue

Users were receiving repeated Todus onboarding and marketing emails, which made the product feel spammy.

### Investigation summary

- The repeated emails come from `scheduleCampaign()` in `apps/server/src/lib/auth.ts`.
- That function schedules a 7-email onboarding/marketing sequence via Resend.
- The local database did not show duplicate records for the same email in `mail0_user`, `mail0_account`, or `mail0_connection`.
- `user_settings` is also unique per `user_id`, so the problem was not duplicate settings rows.
- The sequence was triggered from Better Auth `databaseHooks.account.create.after` and `databaseHooks.account.update.after`.
- Account updates are normal lifecycle events for OAuth-backed accounts and should not re-enroll a user into the onboarding campaign.

### Root cause

Onboarding campaign scheduling was coupled to both account creation and account update events. That made the marketing enrollment path non-idempotent and vulnerable to repeated sends whenever an account record was updated.

### Fix

- Keep connection syncing on both account create and account update.
- Only allow onboarding/marketing campaign scheduling on account creation.
- Keep the existing `welcomeEmailSent` settings flag as a second guardrail for first-time enrollment.

### Architectural note

This change is intentionally conservative. It fixes the spam vector without changing OTP, password reset, verification, or other transactional email flows.

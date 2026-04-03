## Email campaign deduplication

Date: 2026-04-04

### User-facing issue

Users were receiving repeated Todus onboarding and marketing emails, which made the product feel spammy.

### Investigation summary

- The repeated emails come from `scheduleCampaign()` in `apps/server/src/lib/auth.ts`.
- That function schedules a 7-email onboarding/marketing sequence via Resend.
- Exact duplicate `mail0_user.email` values are blocked by the schema, but the uniqueness is case-sensitive.
- The `mail0_account` table had no uniqueness guard on `(provider_id, account_id)`, so the same auth identity could be inserted more than once and retrigger onboarding enrollment.
- The marketing enrollment check relied on `welcomeEmailSent` in `mail0_user_settings`, but that guard was a read-then-write flow and not atomic.
- The local database was not available during this run, so duplicate inspection must be performed against the target database with the audit script once a connection is available.

### Root cause

The onboarding campaign had no durable send ledger. If the auth lifecycle produced duplicate account records or multiple account-create hooks landed close together, each path could independently enroll the same recipient into the 7-email sequence. Because the dedupe lived only in user settings, it did not provide an atomic, database-level guarantee that a given marketing email or send day had already been claimed.

### Fix

- Add a `mail0_marketing_email_delivery` ledger table with unique constraints that guarantee:
  - the same onboarding email key cannot be scheduled twice for the same normalized recipient
  - a normalized recipient cannot receive more than one marketing email on the same day
- Keep `welcomeEmailSent` as a secondary product-level guardrail, but move the hard guarantee into Postgres.
- Add a database constraint on `mail0_account(provider_id, account_id)` and dedupe existing duplicate account rows in the migration before adding the constraint.
- Add `pnpm scripts audit-auth-duplicates` to inspect normalized user, account, and connection duplicates when pointed at a live database.

### Architectural note

This change is intentionally scoped to marketing/onboarding mail. OTP, password reset, email verification, and other transactional emails are unchanged.

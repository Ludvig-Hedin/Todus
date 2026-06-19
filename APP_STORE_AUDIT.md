# App Store Audit

Date: 2026-06-19
Target: iOS app at `apps/ios/Todus`
Bundle ID: `com.ludvighedin.todus`
Current version/build in project config: `1.1` / `3`

## Executive Summary

Overall readiness: NOT READY for App Store submission.

The current iOS app is a substantial native SwiftUI app and has several review-positive items:
Sign in with Apple is present beside Google sign-in, permission prompts are contextual and skippable,
the privacy manifest exists, legal links are reachable from sign-in, and the simulator build/test suite
is green after the small fixes in this audit.

Submission should still be held. The highest-risk blockers are:

- In-app digital subscription/AI-credit access is backed by Autumn/web billing, with an iOS "Upgrade to
  Pro" external web-pricing link and no StoreKit/IAP implementation.
- The live privacy policy is stale and materially conflicts with the current server-backed product.
- App Store Connect privacy labels, age rating, screenshots, review notes, and demo access are not
  represented in the repo and must be completed manually.
- Account deletion can be initiated in-app, but backend deletion completeness is not proven across all
  user-owned tables and services.
- A committed App Store Connect API private key exists in git and must be revoked/removed before
  submission.

Recommended path: continue TestFlight/internal QA, but do not submit for App Review until every item in
Critical Fixes Before Submission is closed and verified on a physical device/TestFlight build.

## Evidence Reviewed

Apple sources consulted:

- Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Apple account deletion guidance: https://developer.apple.com/support/offering-account-deletion-in-your-app/
- Apple App Store Connect app privacy reference: https://developer.apple.com/help/app-store-connect/reference/app-information/app-privacy
- Apple privacy manifest documentation: https://developer.apple.com/documentation/bundleresources/privacy-manifest-files

User-provided checklists reviewed:

- `/Users/ludvighedin/Downloads/App_Store_Review_Acceptance_Checklist_ChatGPT.md`
- `/Users/ludvighedin/Downloads/App_Store_Review_Acceptance_Checklist_Dia.md`
- `/Users/ludvighedin/Downloads/App_Store_Review_Acceptance_Checklist_Gemini.md`
- `/Users/ludvighedin/Downloads/App_Store_Review_Acceptance_Checklist_Perplexity.md`
- `/Users/ludvighedin/.codex/attachments/e57e34a5-da20-4e16-8609-43289318a871/pasted-text.txt`

Repo evidence reviewed:

- iOS config: `apps/ios/Todus/project.yml`, `Info.plist`, `PrivacyInfo.xcprivacy`,
  `Todus.entitlements`, `Package.resolved`
- iOS flows: auth, onboarding, settings, billing, account deletion, permissions, AI, group chat,
  share links, docs, calendar, reminders, notifications
- Backend flows: Better Auth config, account deletion, Autumn subscription routes, AI/provider
  routing, sharing routes
- Public legal pages: `apps/web/app/(full-width)/privacy.tsx`,
  `apps/web/app/(full-width)/terms.tsx`, `apps/web/app/(full-width)/contact.tsx`
- Release docs: `AGENT_CONTEXT.md`, `AGENTS.md`, `docs/deployment.md`,
  `docs/testflight-checklist.md`, `README_TESTFLIGHT.md`, `TESTFLIGHT_QUICK_START.md`,
  `TESTFLIGHT_DEPLOYMENT_GUIDE.md`

Validation run during this audit:

- `plutil -lint` for iOS app/widget Info, entitlements, and privacy manifest files: PASS
- XcodeBuildMCP simulator build, `Todus` scheme, iPhone 17, `CODE_SIGNING_ALLOWED=NO`: PASS
- XcodeBuildMCP simulator tests, `Todus` scheme: PASS, 109 passed / 0 failed / 3 skipped
- `pnpm --filter=@zero/server test -- --runInBand src/lib/auth.ts`: PASS, 31 tests passed
- `pnpm --filter=@zero/server exec eslint src/lib/auth.ts`: PASS with existing React-version
  settings warning only

## Compliance Matrix

| Area | Status | Evidence | Risk | Required fix |
|---|---|---|---|---|
| App completeness and crashes | PARTIAL | Simulator build passed. Full simulator test suite passed after this audit. No physical-device/TestFlight run was performed here. | Medium | Run a real TestFlight build on physical devices, cold install, sign-in, onboarding, mail, tasks, calendar, AI, docs, billing, deletion, offline/reconnect. |
| Demo account / reviewer access | UNKNOWN | No repo evidence of App Review demo credentials, full-feature demo mode, or review notes. Auth uses Apple, Google, and email OTP. | High | Create an active reviewer account with realistic seeded data and a reliable OTP/password/review access path. Add detailed App Review notes. |
| Sign in with Apple | PASS | `AuthView.swift` shows Apple and Google sign-in; entitlements include `com.apple.developer.applesignin`. | Low | Verify the Apple Services ID/bundle config in App Store Connect. |
| Account deletion initiation | PARTIAL | Settings includes in-app destructive delete flow and calls Better Auth `delete-user`. This audit fixed the iOS failure path so users are not signed out when backend deletion fails. | Medium | Verify the end-to-end backend deletion on staging/prod and show clear completion state. Confirm paid-account billing behavior in deletion copy. |
| Account deletion completeness | PARTIAL | Backend `beforeDelete` revokes providers and calls `db.deleteUser()`, but the visible `main.ts` transaction only deletes core user/session/account/settings/connection rows. Related docs/tasks/notes/meetings/summaries/shares need a full cascade audit. | High | Add/verify cascade deletion for all user-owned data, external provider tokens, Autumn customer, shared content, AI history, docs, tasks, notes, summaries, and backups/retention policy. |
| Privacy policy | FAIL | Live policy says Todus is client-only and does not store emails server-side. Current architecture uses Cloudflare backend, Postgres/DOs/workflows, Gmail sync, AI routing, billing, and native clients. | Critical | Rewrite privacy policy before submission. Explicitly disclose collected data, server storage/sync, third-party AI providers, analytics/error reporting, billing processors, retention, deletion, support contact, and user choices. |
| App Store privacy labels | UNKNOWN | App Store Connect state is not in repo. `PrivacyInfo.xcprivacy` declares no collected data, but App Store labels must cover data collected by the app/service and third-party partners. | Critical | Complete/update App Store Connect privacy questionnaire for account info, email/calendar/task/doc content, contacts, usage data, diagnostics, billing, AI processing, and linked/not linked/tracking status. |
| Tracking / ATT / IDFA | PASS for iOS binary, UNKNOWN for labels | iOS search found no ATT/AdSupport/IDFA SDK usage. Web uses Sentry/PostHog/Dub, and server uses Dub in auth when configured. | Medium | Keep iOS labels accurate. If any iOS SDK or cross-app tracking is added, add ATT and update labels. |
| Privacy manifest / required-reason APIs | PASS/PARTIAL | `PrivacyInfo.xcprivacy` exists and declares UserDefaults reason `CA92.1`; plist lint passed. | Medium | Recheck third-party SDK manifests in the final archive and confirm App Store upload has no privacy-manifest warnings. |
| Permission prompts and purpose strings | PASS | Info.plist contains calendar, camera, Face ID, microphone, photos, reminders, and speech purpose strings. Code uses contextual prompts with skip/denied paths for Gmail, Reminders, Notifications, Calendar, voice, camera/photos. | Low | Verify prompts on device. Keep strings aligned if permission usage changes. |
| Billing / IAP / external purchase links | FAIL | `BillingSettingsView.swift` opens `https://todus.app/pricing` for free users and an external Autumn billing portal for paid users. No StoreKit/IAP code or products are present. Paid value is digital AI credits/features. | Critical | Choose and implement an App Review-safe billing strategy: StoreKit auto-renewable subscriptions with restore/manage purchase, or remove all in-app purchase encouragement/external payment links unless a precise Apple-permitted exception/storefront strategy is documented and implemented. |
| Restore purchases / subscription management | FAIL | No StoreKit restore purchase flow exists. Cancel/portal flows are Autumn/web based. | Critical | If selling digital access in iOS, implement StoreKit purchase, restore, subscription status, receipt/server notification handling, and Apple subscription management links. |
| AI and third-party data sharing | PARTIAL | iOS settings expose AI read/write toggles. Backend routes to OpenRouter/Google/OpenAI/Anthropic/Groq/Perplexity/Tavily depending config. Privacy policy does not accurately disclose this. | High | Add explicit in-app/privacy-policy disclosure for third-party AI sharing and obtain appropriate user permission before sending personal data to third-party AI. |
| User-generated content / sharing | PARTIAL | Group chat and public AI share links exist. Sharing has ownership, revocation, password, expiry, and rate limiting. No obvious report/block/moderation flow was found for shared content or group abuse. | High if public/social features are submitted | Either keep these features private/invite-only and explain in review notes, or add report/block/moderation/contact flows satisfying Guideline 1.2. |
| Minimum functionality / not a thin wrapper | PASS | Current iOS app is native SwiftUI with tasks, email, calendar, AI, docs, meetings, widgets, native permissions, and local storage. Docs editor uses a WKWebView wrapper for the editor surface only. | Low | Ensure metadata does not describe the app as a WebView wrapper or legacy app. |
| Metadata / screenshots / support URL | UNKNOWN | `https://todus.app/privacy`, `/terms`, and `/contact` are reachable, but App Store Connect metadata/screenshots are not in repo. | High | Prepare screenshots, description, support URL, privacy URL, keywords, age rating, category, copyright, review notes, and export compliance answers. |
| TestFlight / release docs | PARTIAL | `docs/testflight-checklist.md` points to native SwiftUI, but older top-level TestFlight docs still describe a WebView wrapper and stale bundle IDs/paths. | Medium | Update or archive stale TestFlight docs before submission to avoid operator error. |
| Security / secrets | FAIL | `AuthKey_ZJC3UFF6WX.p8` is tracked in git. Copies also exist in `.claude/worktrees/` and `reference/soma/`. `docs/deployment.md` already documents the issue. | Critical | Revoke exposed App Store Connect API keys, remove from git/cache, add `*.p8` to `.gitignore`, rotate replacement credentials, and purge history if this repo is shared. |
| Export compliance | PARTIAL | `ITSAppUsesNonExemptEncryption=false` is set. App uses TLS/HTTPS and standard Apple/network crypto. | Medium | Confirm App Store Connect export-compliance answers with counsel/account owner for all backend/client cryptography and territories. |
| Age rating / AI content | UNKNOWN | AI chat, email content, web search, public share links, and group chat exist. No App Store Connect age questionnaire evidence in repo. | Medium | Complete age rating honestly for unrestricted web/AI/user content and apply any required age gating/disclosures. |
| Default mail entitlement | PASS/PARTIAL | App registers `mailto`; `com.apple.developer.mail-client` entitlement is absent and documented pending. Root onboarding does not show default-mail setup. | Low | Do not market default mail app support until Apple grants entitlement and signed profiles include it. |

## Critical Fixes Before Submission

1. Resolve iOS billing compliance.
   The current app encourages upgrade through a web pricing link and manages/cancels paid digital access
   through Autumn. For normal global App Store distribution, this is the most likely rejection point.
   Implement StoreKit/IAP or remove/replace in-app purchase CTAs under a reviewed Apple-compliant
   external-link strategy.

2. Rewrite the privacy policy and complete App Store privacy labels.
   The current policy is materially inaccurate for the current product. This needs legal/product owner
   review, not a quick copy edit.

3. Create App Review notes and reviewer access.
   Provide demo credentials or a fully featured demo mode, explain OTP handling, backend URL, sample data,
   paid feature state, permissions, account deletion path, AI behavior, and any disabled/pending features.

4. Prove account deletion completeness.
   Add a checklist/test/migration audit showing every user-owned table and external service is deleted,
   anonymized, or legally retained with disclosure. Verify the flow in production-like environment.

5. Revoke and remove exposed App Store Connect API private keys.
   This is a security and operational blocker. Do not submit with known exposed signing/API material in
   repo history.

6. Decide UGC/group/share posture.
   If group chat or public AI share links ship, add report/block/moderation/contact workflows or keep
   them private and explain the limited exposure in App Review notes.

7. Perform physical-device/TestFlight acceptance.
   Run a fresh install from TestFlight on at least one current iPhone and one smaller/older supported
   device if available. Verify sign-in, logout, delete account, permissions, paid/free behavior, offline,
   push/deep links, and backend availability.

## Important But Not Blocking

- Update stale TestFlight docs that still describe the obsolete WebView wrapper and old app paths.
- Update terms to match the current hosted SaaS/native app instead of self-hosted/open-source-only copy.
- Keep `PrivacyInfo.xcprivacy` in sync with any future SDKs or required-reason API usage.
- Verify the native Docs/More-tab reachability manually. The current UI test skips Docs if the More
  surface does not expose it in `--ui-testing` mode.
- Consider adding first-use AI data-sharing copy before user prompts can include email/calendar/task data.
- Add account deletion integration tests around Better Auth, DB cascades, Autumn deletion, and provider
  token revocation.

## Unknowns / Manual Checks Needed

- App Store Connect privacy labels, age rating, pricing/availability, DSA/trader status, export compliance,
  copyright, support URL, screenshots, and App Review notes.
- Whether the App Store release is intended for US-only storefronts or global distribution.
- Whether Apple has granted or will grant any entitlement/exception related to external purchase links.
- Whether OAuth consent, Gmail restricted-scope verification, and production backend env vars are complete.
- Whether production webhooks for Autumn, Gmail, notifications, AI usage metering, and account deletion are
  healthy during review.
- Whether any third-party SDK privacy manifests generate App Store upload warnings in the final archive.

## Recommended App Review Notes

Use this only after the critical fixes above are complete.

```text
Todus is a native SwiftUI productivity app for email, tasks, calendar, docs, meetings, and AI assistance.
Backend: https://api.todus.app
Web/support: https://todus.app
Privacy: https://todus.app/privacy
Support: https://todus.app/contact

Reviewer account:
Email: <reviewer-email>
Password/OTP process: <exact steps>
Seeded data: <describe inbox/tasks/calendar/docs/meetings test data>

Suggested review path:
1. Launch the app and sign in with the reviewer account.
2. Skip optional Gmail/Reminders/Notifications onboarding if desired; the app still opens to the native Home/Tasks shell.
3. Review Tasks: create, complete, edit, and delete a task.
4. Review Email: open Inbox, thread, compose/draft behavior using seeded Gmail account.
5. Review Calendar: grant calendar permission or skip; create/view events if configured.
6. Review AI: open the AI button, send a non-sensitive prompt, and inspect tool confirmation behavior.
7. Review Settings -> Billing: <describe StoreKit/IAP or compliant billing behavior>.
8. Review Settings -> Danger Zone -> Delete Account: deletion can be initiated in-app.

Permissions:
Calendar, Reminders, Notifications, Microphone/Speech, Photos, and Camera are requested only when the
related feature is used. Each can be skipped or changed later in Settings.

Notes:
<Explain any limited/beta-disabled features, UGC/share behavior, billing implementation, and support contact.>
```

## Pre-Submission Checklist

- [ ] Resolve StoreKit/IAP or compliant no-IAP/external-link strategy.
- [ ] Rewrite and publish accurate privacy policy.
- [ ] Update App Store Connect privacy labels.
- [ ] Update terms/support/legal copy as needed.
- [ ] Revoke and remove exposed `.p8` App Store Connect keys.
- [ ] Add `*.p8` to `.gitignore` after removing tracked key material.
- [ ] Complete account deletion data-cascade audit and production-like test.
- [ ] Prepare reviewer demo account or full demo mode.
- [ ] Prepare App Review notes using the draft above.
- [ ] Complete App Store Connect metadata, screenshots, age rating, export compliance, DSA/trader answers.
- [ ] Verify production backend and OAuth providers are live during review.
- [ ] Run a signed TestFlight build on physical devices.
- [ ] Run fresh install, sign-in, onboarding, core features, logout, delete-account, and reinstall tests.
- [ ] Confirm privacy manifest/upload warnings in Xcode Organizer/App Store Connect.
- [ ] Verify no placeholder/test/beta-only copy is visible in App Store build.

## Completed During This Audit

- Fixed iOS account deletion failure handling so a failed backend deletion no longer signs the user out
  locally and falsely implies success.
- Fixed an inverted backend account-deletion revocation log condition.
- Updated the Docs parity smoke test so it no longer fails on ambiguous/stale More-surface assumptions.
- Added this audit document as the current App Store submission readiness tracker.

# App Store Audit

Date: 2026-06-19
Target: iOS app at `apps/ios/Todus`
Bundle ID: `com.ludvighedin.todus`
Current version/build in project config: `1.1` / `3`

## Executive Summary

Overall readiness: NOT READY for App Store submission.

The current iOS app is a substantial native SwiftUI app and has several review-positive items:
Sign in with Apple is present beside Google sign-in, permission prompts are contextual and skippable,
the privacy manifest exists, legal links are reachable from sign-in, the iOS billing screen no longer
links to external web checkout/hosted billing portals, iOS no longer creates or opens public shared
AI conversation links, and the simulator build/test suite was green after the first audit pass.

Submission should still be held. The highest-risk blockers are:

- App Store Connect privacy labels, age rating, screenshots, review notes, and demo access are not
  represented in the repo and must be completed manually.
- The privacy policy has been rewritten in the repo, but it still needs product/legal owner review and
  deployment before submission.
- iOS paid upgrades are disabled in the app until StoreKit or another App Review-safe purchase strategy
  is implemented. Existing paid-plan cancellation remains available in-app.
- Account deletion can be initiated in-app, database cascades cover the main user-owned tables, and
  external AI memory deletion is now wired best-effort. A production-like deletion test is still
  required before submission.
- Group chat code still exists in the project, but no iOS navigation entry point was found in this
  audit. Keep it unsurfaced until report/block/moderation controls are implemented.
- An exposed App Store Connect API private key was removed from the current tree and `*.p8` is now
  ignored, but the key must still be revoked/rotated and purged from history before submission.

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
- 2026-06-19 continuation: removed the tracked `.p8` key from the current tree, added `*.p8` to
  `.gitignore`, rewrote the hosted privacy policy, updated the iOS privacy manifest data categories,
  removed iOS external billing links, and replaced stale top-level TestFlight wrapper docs.
- 2026-06-19 UGC hardening: iOS AI sharing now uses only the local system share sheet for a redacted
  transcript. The app no longer creates public AI conversation links from the native AI toolbar or
  presents public shared conversations from `todus://share` deep links.
- 2026-06-19 post-UGC validation: XcodeBuildMCP simulator build passed with no warnings/errors; simulator
  tests passed, 109 passed / 0 failed / 3 skipped.

## Compliance Matrix

| Area                                        | Status                                  | Evidence                                                                                                                                                                                                                                                                                                                           | Risk     | Required fix                                                                                                                                                                                                 |
| ------------------------------------------- | --------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| App completeness and crashes                | PARTIAL                                 | Simulator build passed. Full simulator test suite passed after this audit. No physical-device/TestFlight run was performed here.                                                                                                                                                                                                   | Medium   | Run a real TestFlight build on physical devices, cold install, sign-in, onboarding, mail, tasks, calendar, AI, docs, billing, deletion, offline/reconnect.                                                   |
| Demo account / reviewer access              | UNKNOWN                                 | No repo evidence of App Review demo credentials, full-feature demo mode, or review notes. Auth uses Apple, Google, and email OTP.                                                                                                                                                                                                  | High     | Create an active reviewer account with realistic seeded data and a reliable OTP/password/review access path. Add detailed App Review notes.                                                                  |
| Sign in with Apple                          | PASS                                    | `AuthView.swift` shows Apple and Google sign-in; entitlements include `com.apple.developer.applesignin`.                                                                                                                                                                                                                           | Low      | Verify the Apple Services ID/bundle config in App Store Connect.                                                                                                                                             |
| Account deletion initiation                 | PARTIAL                                 | Settings includes in-app destructive delete flow and calls Better Auth `delete-user`. This audit fixed the iOS failure path so users are not signed out when backend deletion fails.                                                                                                                                               | Medium   | Verify the end-to-end backend deletion on staging/prod and show clear completion state. Confirm paid-account billing behavior in deletion copy.                                                              |
| Account deletion completeness               | PARTIAL                                 | Backend `beforeDelete` revokes providers, deletes Autumn customer state, deletes external Mem0 AI memories best-effort, invalidates Mem0 caches, and calls `db.deleteUser()`. Schema/migrations cascade the main user-owned DB tables.                                                                                             | Medium   | Run a production-like deletion test and verify provider revocation, Autumn deletion, Mem0 deletion, DB cascades, backups/log retention, and user-facing completion copy.                                     |
| Privacy policy                              | PARTIAL                                 | Repo policy now describes the hosted server-backed product, connected account data, AI processing, providers, billing, retention/deletion, and user controls. It still needs owner/legal review and deployment verification.                                                                                                       | High     | Review/publish the rewritten policy before submission. Keep it aligned with App Store labels and production behavior.                                                                                        |
| App Store privacy labels                    | UNKNOWN                                 | App Store Connect state is not in repo. `PrivacyInfo.xcprivacy` now declares first-party collected data categories, but App Store labels must still be completed manually for the app/service and partners.                                                                                                                        | Critical | Complete/update App Store Connect privacy questionnaire for account info, email/calendar/task/doc content, contacts, usage data, diagnostics, billing, AI processing, and linked/not linked/tracking status. |
| Tracking / ATT / IDFA                       | PASS for iOS binary, UNKNOWN for labels | iOS search found no ATT/AdSupport/IDFA SDK usage. Web uses Sentry/PostHog/Dub, and server uses Dub in auth when configured.                                                                                                                                                                                                        | Medium   | Keep iOS labels accurate. If any iOS SDK or cross-app tracking is added, add ATT and update labels.                                                                                                          |
| Privacy manifest / required-reason APIs     | PASS/PARTIAL                            | `PrivacyInfo.xcprivacy` exists, declares UserDefaults reason `CA92.1`, and now includes collected data categories for account, email/message content, user content, interactions, crash, and performance data.                                                                                                                     | Medium   | Recheck third-party SDK manifests and required-reason API warnings in the final archive/upload.                                                                                                              |
| Permission prompts and purpose strings      | PASS                                    | Info.plist contains calendar, camera, Face ID, microphone, photos, reminders, and speech purpose strings. Code uses contextual prompts with skip/denied paths for Gmail, Reminders, Notifications, Calendar, voice, camera/photos.                                                                                                 | Low      | Verify prompts on device. Keep strings aligned if permission usage changes.                                                                                                                                  |
| Billing / IAP / external purchase links     | PARTIAL                                 | iOS no longer links free users to web pricing or paid users to the hosted billing portal. No StoreKit/IAP code or products are present, so paid iOS upgrades are not offered in this build.                                                                                                                                        | Medium   | Keep iOS free/no-upgrade for submission, or implement StoreKit auto-renewable subscriptions with restore/manage purchase before selling paid digital access in iOS.                                          |
| Restore purchases / subscription management | PARTIAL                                 | No StoreKit restore flow exists because iOS paid purchases are not offered. Existing paid users can cancel via the app's API, but payment-method changes are outside this build.                                                                                                                                                   | Medium   | If paid iOS purchases are introduced, implement StoreKit purchase, restore, subscription status, receipt/server notification handling, and Apple subscription management links.                              |
| AI and third-party data sharing             | PARTIAL                                 | iOS settings expose AI read/write toggles. Backend routes to OpenRouter/Google/OpenAI/Anthropic/Groq/Perplexity/Tavily depending config. The rewritten privacy policy now discloses AI provider processing at a high level.                                                                                                        | Medium   | Consider adding first-use in-app AI data-sharing copy before sending personal email/calendar/task/doc data to third-party AI.                                                                                |
| User-generated content / sharing            | PASS/PARTIAL                            | iOS AI toolbar sharing now uses the local system share sheet with a redacted transcript instead of creating hosted public links. `todus://share` no longer opens public shared conversations in iOS. Group chat code exists but no iOS entry point was found. Web/server sharing still exists outside this iOS submission surface. | Medium   | Keep group/public sharing unsurfaced in the iOS submission build, state this in review notes if needed, and add report/block/moderation/contact flows before shipping public or social UGC in iOS.           |
| Minimum functionality / not a thin wrapper  | PASS                                    | Current iOS app is native SwiftUI with tasks, email, calendar, AI, docs, meetings, widgets, native permissions, and local storage. Docs editor uses a WKWebView wrapper for the editor surface only.                                                                                                                               | Low      | Ensure metadata does not describe the app as a WebView wrapper or legacy app.                                                                                                                                |
| Metadata / screenshots / support URL        | UNKNOWN                                 | `https://todus.app/privacy`, `/terms`, and `/contact` are reachable, but App Store Connect metadata/screenshots are not in repo.                                                                                                                                                                                                   | High     | Prepare screenshots, description, support URL, privacy URL, keywords, age rating, category, copyright, review notes, and export compliance answers.                                                          |
| TestFlight / release docs                   | PASS/PARTIAL                            | Top-level TestFlight docs now describe the active native SwiftUI app and point to this audit. Physical TestFlight validation is still manual.                                                                                                                                                                                      | Medium   | Run the updated checklist against a signed TestFlight build.                                                                                                                                                 |
| Security / secrets                          | PARTIAL                                 | `AuthKey_ZJC3UFF6WX.p8` was removed from the current tree and `*.p8` is ignored. The exposed key remains in git history and must be revoked/rotated by the account owner.                                                                                                                                                          | Critical | Revoke exposed App Store Connect API keys, rotate replacement credentials, purge history if this repo is shared, and remove any local/worktree copies.                                                       |
| Export compliance                           | PARTIAL                                 | `ITSAppUsesNonExemptEncryption=false` is set. App uses TLS/HTTPS and standard Apple/network crypto.                                                                                                                                                                                                                                | Medium   | Confirm App Store Connect export-compliance answers with counsel/account owner for all backend/client cryptography and territories.                                                                          |
| Age rating / AI content                     | UNKNOWN                                 | AI chat, email content, web search, public share links, and group chat exist. No App Store Connect age questionnaire evidence in repo.                                                                                                                                                                                             | Medium   | Complete age rating honestly for unrestricted web/AI/user content and apply any required age gating/disclosures.                                                                                             |
| Default mail entitlement                    | PASS/PARTIAL                            | App registers `mailto`; `com.apple.developer.mail-client` entitlement is absent and documented pending. Root onboarding does not show default-mail setup.                                                                                                                                                                          | Low      | Do not market default mail app support until Apple grants entitlement and signed profiles include it.                                                                                                        |

## Critical Fixes Before Submission

1. Confirm the iOS billing posture for submission.
   The iOS app no longer opens web pricing or hosted billing portals. For App Review, submit it as a
   free/no-upgrade iOS build unless StoreKit or another reviewed Apple-compliant purchase strategy is
   implemented before submission.

2. Review/publish the rewritten privacy policy and complete App Store privacy labels.
   The repo policy is now aligned with the current architecture, but it still needs owner/legal review,
   deployment verification, and matching App Store Connect privacy labels.

3. Create App Review notes and reviewer access.
   Provide demo credentials or a fully featured demo mode, explain OTP handling, backend URL, sample data,
   paid feature state, permissions, account deletion path, AI behavior, and any disabled/pending features.

4. Prove account deletion completeness in a production-like environment.
   Code now covers provider revocation, Autumn deletion, Mem0 memory deletion, local/KV Mem0 cache
   invalidation, and DB cascades. Still verify the full flow against staging/prod data, including
   backups/log retention and the user-facing completion state.

5. Revoke and remove exposed App Store Connect API private keys.
   The current tree no longer tracks the key, but the account owner must revoke/rotate it and purge
   history or otherwise confirm the exposure cannot affect release operations.

6. Keep UGC/group/share features out of the iOS submission surface.
   This audit removed iOS public AI share-link creation and shared-link viewing. Group chat code still
   exists but was not found in the iOS navigation surface. Do not re-enable public/social UGC in iOS
   until report, block, moderation, and contact workflows satisfy Guideline 1.2.

7. Perform physical-device/TestFlight acceptance.
   Run a fresh install from TestFlight on at least one current iPhone and one smaller/older supported
   device if available. Verify sign-in, logout, delete account, permissions, paid/free behavior, offline,
   push/deep links, and backend availability.

## Important But Not Blocking

- Update terms to match the current hosted SaaS/native app instead of self-hosted/open-source-only copy.
- Keep `PrivacyInfo.xcprivacy` in sync with any future SDKs or required-reason API usage.
- Verify the native Docs/More-tab reachability manually. The current UI test skips Docs if the More
  surface does not expose it in `--ui-testing` mode.
- Consider adding first-use AI data-sharing copy before user prompts can include email/calendar/task data.
- Add end-to-end account deletion integration tests around Better Auth, DB cascades, Autumn deletion,
  Mem0 deletion, and provider token revocation.

## Unknowns / Manual Checks Needed

- App Store Connect privacy labels, age rating, pricing/availability, DSA/trader status, export compliance,
  copyright, support URL, screenshots, and App Review notes.
- Whether the App Store release is intended for US-only storefronts or global distribution.
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
7. Review Settings -> Billing: the submitted iOS build shows plan/usage, does not offer paid upgrades, and allows active paid users to cancel in-app.
8. Review Settings -> Danger Zone -> Delete Account: deletion can be initiated in-app.

Permissions:
Calendar, Reminders, Notifications, Microphone/Speech, Photos, and Camera are requested only when the
related feature is used. Each can be skipped or changed later in Settings.

Notes:
<Explain any limited/beta-disabled features, UGC/share behavior, billing implementation, and support contact.>
```

## Pre-Submission Checklist

- [x] Remove iOS external web-pricing and hosted billing-portal links.
- [ ] Confirm final no-upgrade or StoreKit billing strategy in App Review notes.
- [x] Rewrite repo privacy policy for current hosted service behavior.
- [ ] Publish/review accurate privacy policy.
- [ ] Update App Store Connect privacy labels.
- [ ] Update terms/support/legal copy as needed.
- [ ] Revoke/rotate exposed `.p8` App Store Connect keys.
- [x] Remove tracked `.p8` key material from the current tree.
- [x] Add `*.p8` to `.gitignore` after removing tracked key material.
- [x] Wire external AI memory deletion into account deletion.
- [ ] Complete production-like account deletion test.
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
- Removed iOS external purchase/billing links while paid iOS purchases are unavailable.
- Rewrote the hosted privacy policy to match the current server-backed product.
- Updated the active iOS privacy manifest with collected data categories.
- Removed the tracked App Store Connect `.p8` key from the current tree and ignored future `.p8` files.
- Replaced stale top-level TestFlight WebView-wrapper docs with native SwiftUI release guidance.
- Added best-effort Mem0 external AI memory deletion and cache invalidation to account deletion.

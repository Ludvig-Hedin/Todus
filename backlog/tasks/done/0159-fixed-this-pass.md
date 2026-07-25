---
id: 0159
title: "Fixed this pass"
status: done
tags: [code-review-backlog]
files: [main.ts, lib/ai-profile.ts, trpc/routes/assistant.ts, lib/thread-classification.ts, assistant.ts, mail-assistant.ts, pipelines.ts, hooks/use-optimistic-actions.ts]
created: 2026-06-13
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Backlog resolution pass — 2026-06-13 (whole-repo)

## Fixed this pass

**Server (`apps/server/src`)**
- `main.ts` — `.well-known/oauth-authorization-server` missing leading slash → 404 (added `/`).
- `main.ts` — `processExpiredSubscriptions` leaked the Hyperdrive connection if `findMany` threw (wrapped in try/finally).
- `main.ts` — `[SCHEDULED] Processed ${allAccounts.keys.length}` always logged 0 (→ `.length`).
- `main.ts` — `a8n/notify/:providerId` returned `undefined` (→ 500/404) for non-google providers (added explicit 200 fallback).
- `main.ts` — **send-email-queue dropped scheduled emails on transient failure** (catch deleted status+payload then acked); now keeps payload and `msg.retry()`s.
- `main.ts` (B-003, security) — native refresh-token fallback ignored `expiresAt`; bounded to a 15-min grace window so a leaked long-expired token can't resurrect a session.
- `lib/ai-profile.ts` (B-024) — sanitize user `name`/`email` before prompt interpolation (strip backticks/headers/newlines); (B-027) add `timeZoneName` so local time isn't zone-ambiguous.
- `trpc/routes/assistant.ts` (B-020) — `extractVerificationCode` fallback now requires a verification keyword nearby + rejects zips/years/phones (prefers null over a wrong code); (B-021) `extractReceiptDetails` prefers a label-anchored (Total/Amount paid/…) amount before any currency number.
- `lib/thread-classification.ts` (B-012, NEW) — extracted the duplicated/drifting `classifyThreadKind` + keyword/sender regexes; `assistant.ts` + `mail-assistant.ts` now import the shared (superset) module.
- `pipelines.ts` (B-023) — extracted `getUserAutomationPolicy(userId)`; both the Effect and imperative paths call it (dropped the duplicate fallback).

**Web (`apps/web`)**
- `hooks/use-optimistic-actions.ts` — cleanup branch checked `=== 1` AFTER the delete (1→0 never fired) → optimistic-actions atom leak + stuck `shouldHide`; fixed to `=== 0`.
- `components/ui/bimi-avatar.tsx` (B-013) — re-applied the dropped favicon-URL cap (`.slice(0, MAX_FAVICON_URLS)`, bumped to 8) so a sender no longer fires 20-30+ sequential favicon GETs.
- `app/(routes)/mail/tasks/page.tsx` (B-039) — removed the redundant unconditional `invalidateQueries` on task create (was thrashing the optimistic cache patch).

**iOS (`apps/ios/Todus`)**
- `Services/Email/EmailService.swift` (B-016) — `checkConnection` no longer marks `hasResolvedConnection` true on timeout (was stranding connected users on the connect screen); (EM-5) `connectGmail` multi-account now polls until the new connection lands before reporting success; (EM-11) `performLoadThreads` sorts merged pages by date desc (pinned `mergePages` contract + test left intact).
- `Features/Email/SenderAvatarView.swift` (EM-2) — capped the favicon waterfall to 4 candidates; (EM-4) letter-only registry brands now fall through to the favicon waterfall (brand-tinted initials as base) instead of dead-ending on gray initials.
- `Features/Email/EmailThreadView.swift` (EM-12) — webview deferred re-measure is a cancellable `DispatchWorkItem`, cancelled in `dismantleUIView`.
- `Features/Email/EmailComposeView.swift` (EM-10) — a removed From-connection no longer silently sends from the backend default: resets to default + blocks send with a notice alert.
- `Features/Search/GlobalSearchView.swift` (B-0601b-2) — People results use `SenderAvatarView` (real avatars) instead of a custom gray-initials ZStack.

**macOS (`apps/macos/TodusMac`)**
- `Views/Email/MacEmailComposeView.swift` (QA-0608-3) — "Start fresh" resets `didApplySignature` + re-applies signature; (B-029) `.onDisappear` cancels the autosave task so a late write can't resurrect a cleared draft.
- `App/MacOnboardingViews.swift` (QA-0608-7) — Gmail onboarding auto-advances when already connected.
- `Views/Email/MacEmailThreadView.swift` (MAC-2) — message list is `LazyVStack` (bounded WebView build cost on long threads).
- `Views/AI/ChatUISpec/CardViews.swift` — AI compose-card CC/BCC now have add-fields (mirrors the iOS fix).
- `Services/Email/EmailService.swift` (QA-0608-9) — read-state now also patches `threadDetailCache` so search-opened threads reflect read/unread (with symmetric rollback).

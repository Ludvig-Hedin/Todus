---
id: 0116
title: "Medium severity"
status: done
tags: [code-review, code-review-backlog]
files: [apps/macos/TodusMac/Services/Tasks/LocalTaskParsingService.swift, apps/server/src/lib/thread-classifier.ts, bimi-avatar.tsx]
created: 2026-05-02
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-02 — Full-repo Review

## Medium severity

_Closed by the 2026-06-13 backlog resolution pass (`CODE_REVIEW_BACKLOG.md` → "No open code defects remain": every code-defect item was fixed, built, tested and committed in passes 1-6). Re-open if this finding is still reproducible._


### B-010 — iOS avatar disk cache key uses `String.hashValue`
- **File:** `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift:13` · **Type:** bug · **Risk:** medium · **Status:** open
- **Summary:** `dataKey` interpolates `urlString.hashValue`, which Swift randomizes per process launch. The cache entry written this run is unreadable next launch — the doc-comment promise of "renders correctly when device is offline" never holds across launches. Orphaned keys also accumulate in `UserDefaults`.
- **Approach:** `import CryptoKit`, use `SHA256.hash(data: Data(urlString.utf8))` formatted as hex.

### B-011 — `LocalTaskParsingService.hasDateKeyword` wrong for "today"/"idag"
- **File:** `apps/ios/Todus/Todus/Services/Parsing/LocalTaskParsingService.swift:77` (mirrored in macOS) · **Type:** bug · **Risk:** medium · **Status:** open
- **Summary:** When the user types `today 14`, the relative-marker step matches `today` (offset 0) and sets `foundDateKeyword = true`, but `baseDate == now`. Line 77 derives `hasDateKeyword` from `baseDate != now`, which is `false`, and `findTimeMatch` runs in the more conservative mode.
- **Approach:** `let hasDateKeyword = foundDateKeyword || (baseDate != now)`. Add a unit test for `today 14` → today @ 14:00. Mirror to the macOS copy at `apps/macos/TodusMac/Services/Tasks/LocalTaskParsingService.swift`.

### B-012 — `classifyThreadKind` duplicated and already drifting between two routers
- **Files:** `apps/server/src/trpc/routes/assistant.ts:317-323`, `apps/server/src/trpc/routes/mail-assistant.ts:81-87` · **Type:** correctness / maintainability · **Risk:** medium · **Status:** open
- **Summary:** Both routers reimplement `VERIFICATION_KEYWORDS`, `RECEIPT_KEYWORDS`, `MARKETING_SENDER_PATTERN` and `classifyThreadKind`. The mail-assistant copy already adds `MARKETING_SENDER_PATTERN.test(senderEmail)` to `isAutomatedSender`; the assistant.ts copy does not. Same thread classifies differently across endpoints.
- **Approach:** Hoist to `apps/server/src/lib/thread-classifier.ts` and import from both. Add unit tests covering verification, receipt, marketing, notification.

### B-013 — `bimi-avatar.tsx` URL cap removed; constant still declared
- **File:** `apps/web/components/ui/bimi-avatar.tsx:8` (dead constant), `:122` (cap removed) · **Type:** performance · **Risk:** medium · **Status:** open
- **Summary:** `MAX_FAVICON_URLS = 6` declared but no longer used (the diff removed the `.slice(...)`). With Clearbit + icon.horse + DDG + Google × {bare, www} × multiple domain candidates, a sender like `foo@a.b.example.com` can yield 30+ URLs, each tried sequentially via `<img onError>` chain.
- **Approach:** Restore the cap (possibly bump to 8–10) or delete the unused constant if uncapped is intentional.

### B-014 — `bimi-avatar.tsx` leaks recipient social graph to four third parties
- **File:** `apps/web/components/ui/bimi-avatar.tsx:98-119` · **Type:** privacy · **Risk:** medium · **Status:** open
- **Summary:** Every non-personal sender domain triggers requests to `logo.clearbit.com`, `icon.horse`, `icons.duckduckgo.com`, `google.com/s2/favicons` from the user's browser. Meaningful expansion of the third-party request graph.
- **Approach:** Proxy via the backend `avatar` tRPC route (which already returns `fallbackUrls`), so the client only hits same-origin URLs. Or gate behind the `externalImages` user setting.

### B-015 — Sender-avatar / Gravatar fallback expands third-party PII surface (server)
- **File:** `apps/server/src/lib/sender-avatar.ts:367-419` · **Type:** privacy + reliability · **Risk:** medium · **Status:** open
- **Summary:** Composes Gravatar URLs from raw user-supplied emails (hash-based; not generally reversible but Gravatar lookups can confirm known emails). Combined with Clearbit/icon.horse/DDG, the user's senders are queried against four external services per resolution. No caching layer.
- **Approach:** Gate behind `externalImages` user setting; cache resolution per-domain in KV with 24h TTL.

### B-016 — iOS `checkConnection` flips `hasResolvedConnection = true` even on timeout
- **File:** `apps/ios/Todus/Todus/Services/Email/EmailService.swift:1014-1042` · **Type:** bug · **Risk:** medium · **Status:** open
- **Summary:** `defer { hasResolvedConnection = true }` runs even when the API call throws and `hasConnection` was never set. A single transient 8-second timeout can lock the user into a stale `hasConnection=false` for 30 s because the next call within the cooldown window will skip re-checking.
- **Approach:** Move `hasResolvedConnection = true` into the success branch; or invalidate it on throw.

### B-017 — Workflow durability: automation-policy fetch outside `step.do`
- **File:** `apps/server/src/pipelines.ts:622-637` · **Type:** workflow durability · **Risk:** medium · **Status:** open
- **Summary:** Inside the workflow generator, `Effect.tryPromise` reads automation policy directly. On replay after a crash, this is non-deterministic — if the user toggled settings between runs, replay sees a different policy and may register a different set of `WorkflowDefinition`s.
- **Approach:** Wrap as `step.do('fetch-automation-policy', () => …)`. Verify whether `Effect.tryPromise` already memoizes via the surrounding step infrastructure.

### B-018 — `triggerServerSync` task captures `@MainActor` class without Sendable
- **File:** `apps/ios/Todus/Todus/Services/Email/EmailService.swift:372` (and macOS mirror) · **Type:** Swift 6 strict-concurrency safety · **Risk:** medium · **Status:** open
- **Summary:** `Task { [api] in … }` captures `TodosAPIClient`, which is not declared `Sendable`. Today this works because `api.trpcMutation` is `@MainActor`-isolated, but the closure capture itself is what strict concurrency flags.
- **Approach:** Either declare `TodosAPIClient` `@unchecked Sendable` with documented contract, or refactor `trpcMutation` to a free async function.

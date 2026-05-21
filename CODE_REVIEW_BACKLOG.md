# Code Review Backlog

Last updated: 2026-05-20

---

# 2026-05-20 — Bug Hunt: apps/web main user flows

Scope: auth (login/signup/OTP), mail layout, [folder] route, compose, chat, calendar, tasks, optimistic actions.

## Auto-fixed (1)

| File:line | Severity | What changed |
|-----------|----------|--------------|
| `apps/web/app/(routes)/mail/calendar/page.tsx:174-181` | error | useEffect deps included `displayMonth`, so any user-initiated month-pagination via Calendar's `onMonthChange` re-fired the effect and snapped `displayMonth` back to `selectedDate`'s month. Users could not paginate the picker without also clicking a date. Removed `displayMonth` from deps (eslint-disable for exhaustive-deps); effect now runs only on `selectedDate` change. |

## Needs human review (1)

| File:line | Severity | Problem | Suggested fix |
|-----------|----------|---------|---------------|
| `apps/web/hooks/use-optimistic-actions.ts:347` | warning | `typeActions?.size === 1` is checked AFTER `typeActions.delete(pendingActionId)` on the previous line mutates the same Set reference. Branch fires only when one OTHER pending action of the same type remains in flight. Single-action case (Set 1 → 0) never enters the branch, so `refreshData()`, `invalidateFolderLists()`, and `removeOptimisticAction()` are skipped: jotai `optimisticActionsAtom` grows unboundedly across a session (memory leak), MOVE/SNOOZE/UNSNOOZE/DELETE_DRAFT actions leave `shouldHide=true` forever in optimistic state, and server folder caches drift until the 5-minute stale window expires. | Almost certainly `=== 0` (i.e. this was the last in flight). Verify intent against the action's design — the current `=== 1` may have been left over from a different cleanup model. TODO comment inserted inline. |

## Investigated, not bugs (false positives from investigator subagent)

- **`apps/web/components/mail/thread-display.tsx:212`** — `Math.max(1, focusedIndex + 1)`. `focusedIndex` is guaranteed `>= 0` by the `focusedIndex === null` early return on the previous line, so the clamp is a no-op (redundant but harmless).
- **`apps/web/components/mail/mail-list.tsx:177`** — `setFocusedIndex(focusedIndex)`. After the optimistic move/archive removes the current row, the list shifts left by one, so the OLD index now points at the formerly-next sibling — keeping the index intentional.
- **`apps/web/components/create/create-email.tsx:91`** — Calling `useActiveConnection()` twice (lines 79 + 91) produces two bindings (`activeConnection`, `activeAccount`) that resolve to the same react-query cache entry. Wasteful but not a bug; both used in different fallback chains for `userEmail` / `userName`.
- **`apps/web/components/create/email-composer.tsx:480`** — `editor.getHTML() === initialMessage.trim()` is a defensive double-check alongside the plain-text comparison on line 479. `initialMessage` may be HTML (draft body) or plain text (replies) depending on call site; the dual comparison catches both forms.
- **`apps/web/app/(routes)/mail/[folder]/page.tsx:59-61`** — The `else { setIsLabelValid(false) }` branch when `userLabels` is falsy. `useLabels()` returns `userLabels: []` (empty array, truthy) even on error/loading, so this branch is unreachable dead code. UI's auto-redirect timer still fires via the `if (userLabels)` path (empty array passes `checkLabelExists` returning false, then starts the timer).

---

# 2026-05-20 — Bug Hunt: macOS app main user flows

Scope: auth/onboarding, email inbox/thread/compose, tasks, calendar, AI chat/voice, docs, search, notifications, meetings.

## Auto-fixed (2)

| File:line | Severity | What changed |
|-----------|----------|--------------|
| `apps/macos/TodusMac/Views/Email/MacEmailComposeView.swift:380` | error | Reply All never auto-expanded Cc/Bcc when `draft.cc` was empty. The branch `if cc.isEmpty && nav != "Reply All" {} else if !cc.isEmpty { show }` had an empty if-body, so the `navigationTitle == "Reply All"` check was dead. Replaced with `if navigationTitle == "Reply All" || !draft.cc.isEmpty { showCcBcc = true }`. |
| `apps/macos/TodusMac/App/MacOnboardingViews.swift:200` | error | Reminders onboarding treated `.writeOnly` as denied, but `MacAppServices.requestRemindersPermissionIfNeeded()` (line 736) accepts `.writeOnly` as authorized. Users granting write-only access saw "Permission was not granted" while underlying sync would have worked. Moved `.writeOnly` into the authorized branch. |

## Needs human review (3)

| File:line | Severity | Problem | Suggested fix |
|-----------|----------|---------|---------------|
| `apps/macos/TodusMac/Services/Tasks/LocalTaskParsingService.swift:75` | warning | `daysAhead <= 0 { daysAhead += 7 }` — typing "monday" on a Monday schedules next Monday, not today. May be intentional but worth surfacing to product. | Decide policy: (a) same-day-keyword keeps today, (b) same-day-keyword rolls forward. If (a), change to `daysAhead < 0`. |
| `apps/macos/TodusMac/Views/Email/MacEmailThreadView.swift:245-262` | warning | Compose sheet renders empty content if `detail?.messages.last` is nil when `showCompose=true`. User can trigger an empty 520x380 sheet. | Guard `showCompose = true` behind a `detail?.messages.last != nil` precondition, or add a placeholder/error state inside the sheet. |
| `apps/macos/TodusMac/Services/Voice/GeminiLiveProvider.swift:271-279` | info | Captures `let task = self.webSocketTask` at 271 but then dereferences `self.webSocketTask` again at 273 and 278 before nilling. Single-actor so unlikely race, but inconsistent. | Use the captured `task` reference throughout, then nil `self.webSocketTask` once. |

## Investigated, not bugs

- **`apps/macos/TodusMac/Services/Drafts/MacDraftService.swift:173`** — `draft.connectionId` is non-optional `String` per `DraftRecord`; `.trimmingCharacters` is safe.
- **`apps/macos/TodusMac/Services/Voice/VoiceSessionCoordinator.swift:454`** — `executeTool` IS awaited inside the Task closure; no missing await.
- **`apps/macos/TodusMac/Views/Calendar/MacCalendarView.swift:1290-1294`** — Hour overflow when minute rounding hits 60: Foundation `Calendar.date(from:)` normalizes out-of-range components (e.g. hour=24 → next day 00:00). Safe.
- **`apps/macos/TodusMac/Views/Notifications/MacNotificationCenterView.swift:516`** — Request-ID guard correctly captures ID before await and compares after; not a race.
- **`apps/macos/TodusMac/Domain/TaskSmartSort.swift:72`** — Today-bucket-before-overdue ordering is the documented intent (`.today: "Needs attention now"`).
- **`apps/macos/TodusMac/Views/Meetings/MacMeetingDetailView.swift:458`** — Calling `loadMeeting()` after `generateSummary` failure is intentional refresh; `actionError` is also set.



## Open Items

| ID | Title | Area | Type | Impact | Risk | Status | Summary |
|----|-------|------|------|--------|------|--------|---------|
| 001 | Inline TaskItem duplicated in home/page.tsx | web/home | design-debt | internal | low | open | `home/page.tsx` defines its own inline `TaskItem` component instead of importing the shared `components/tasks/task-item.tsx`. Both work correctly but will diverge over time. Fix: import from `@/components/tasks/task-item` and remove the inline definition. |

---

# 2026-05-02 — Full-repo Review

Scope: uncommitted local changes (~80 modified files + new files) plus last 3 commits (`d8d471c7`, `07433b25`, `8fd1cf0e`). Reviewed iOS app + Swift packages, macOS app, Cloudflare Worker backend, web product (`apps/web`), and marketing site (`new-website`). `apps/mail/` (read-only archive) excluded.

## Auto-fixed in this run

| ID | File:line | Status | What changed |
|----|-----------|--------|--------------|
| AF-1 | `apps/macos/TodusMac/Domain/SnoozeOption.swift:35` | auto-fixed | Replaced dead `var components = calendar.dateComponents(...)` (only `.weekday` used) with single `calendar.component(.weekday, from: now)` call. No behavior change. |
| AF-2 | `apps/macos/TodusMac/Services/Email/EmailService.swift:218` | auto-fixed | Doc-comment said "detached task" but the implementation uses `Task { ... }` (an independent top-level Task, not `Task.detached`). Updated wording to match the inline comment further down. Comment-only. |

## High severity (block before merge)

### B-001 — Mixed package-manager config in `package.json` will break installs
- **Area:** repo root · **Type:** repo hygiene / build break · **Risk:** high · **Status:** open
- **Files:** `package.json`, untracked `bun.lock`
- **Summary:** New diff adds `workspaces.catalog` (bun-only syntax) and `patchedDependencies` (pnpm syntax) to the same `package.json`, while a `bun.lock` (~1.4 MB) sits alongside the canonical `pnpm-lock.yaml` (~1.0 MB). `CLAUDE.md` and every script standardize on pnpm. `pnpm install` will ignore the catalog → silently diverge from `bun install` resolutions; `pnpm.patchedDependencies` should be nested under `"pnpm": { ... }` in pnpm v9+; referenced `patches/novel.patch` may not exist.
- **Approach:** Pick one package manager. If pnpm: revert `package.json` block, move catalog entries to `pnpm-workspace.yaml`'s `catalog:`, ensure `patchedDependencies` correctly nested. Drop `bun.lock`. If bun: drop `pnpm-lock.yaml`, rewrite scripts and `CLAUDE.md`.

### B-002 — Settings `location` field may not persist end-to-end
- **Area:** apps/web, apps/server, apps/ios, apps/macos · **Type:** correctness / UX · **Risk:** medium · **Status:** open
- **Files:** `apps/web/app/(routes)/settings/general/page.tsx:152`, `apps/server/src/lib/schemas.ts:195`, plus iOS/macOS settings sheets
- **Summary:** The `location` form field is rendered, defaulted, and the Zod schema accepts it (`z.string().default('')`). What's not visible in the diff is whether the web mutation payload, the tRPC settings router write path, the iOS settings sheet, and the macOS settings sheet all actually transmit/receive the new field. If any link is missing, the user types and saves and the value silently disappears.
- **Approach:** Trace `location` from each platform's settings UI through to a DB write and confirm round-trip. Add at least one parity screenshot test or unit test pinning the wire format.

### B-003 — Refresh-token fallback ignores `expiresAt`
- **Area:** apps/server (auth) · **Type:** security · **Risk:** high · **Status:** open
- **File:** `apps/server/src/main.ts:1197-1212`
- **Summary:** New fallback selects ANY session row for `sessionUser.id` whose `token === trimmedRefreshToken`, ignoring `expiresAt`. Comment justifies this for replication lag and freshly-rotated tokens, but it also means an attacker who obtains a long-expired session token (e.g. from old logs/backups) could pair it with a current Bearer for the same user and resurrect the expired session for downstream account-linking flows.
- **Approach:** Bound the fallback to a short window (e.g. `expiresAt > now() - 15 min`). Verify whether Better Auth's `linkSocialAccount` re-validates the session token; if not, this is exploitable.

### B-004 — macOS compose body sent as raw markdown — recipients see `**bold**` literals
- **Area:** apps/macos email compose · **Type:** correctness / UX · **Risk:** medium · **Status:** open
- **Files:** `apps/macos/TodusMac/Views/Email/MacEmailComposeView.swift:411-470`, `apps/macos/TodusMac/Services/Email/EmailService.swift:818`
- **Summary:** The new formatting toolbar inserts `**`, `_`, `# `, `- `, `> ` directly into `draft.body`. `mail.send` is called with `message: draft.body` unchanged. The backend treats it as plain text or HTML, not markdown — recipients see the markdown literals.
- **Approach:** Render toolbar inserts as inline HTML (`<b>`, `<i>`, `<h1>`, `<ul><li>`) before sending, or convert markdown → HTML on send. The toolbar should also wrap the *selected text* rather than appending a placeholder at end of body.

### B-005 — macOS compose "From" account selector is non-functional
- **Area:** apps/macos email compose · **Type:** correctness · **Risk:** medium · **Status:** open
- **Files:** `apps/macos/TodusMac/Services/Email/EmailService.swift:805-823`, `apps/macos/TodusMac/Domain/EmailModels.swift:158`
- **Summary:** `EmailDraft.fromConnectionId` is captured by the new "From" menu but `sendEmail(_:)` never serializes it into `SendEmailInput`, and `SendEmailInput` has no `connectionId` field. Multi-account users believe they're sending from the selected account; every send actually uses the backend default.
- **Approach:** Add `connectionId: String?` to `SendEmailInput`, populate from `draft.fromConnectionId`, confirm the backend `mail.send` accepts it (web/iOS likely already do).

## Medium severity

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

## Low severity / suggestions

| ID | File:line | Type | Summary |
|----|-----------|------|---------|
| B-020 | `apps/server/src/trpc/routes/assistant.ts:432-453` | correctness | `extractVerificationCode` fallback regex picks any 4-8 digit number — order numbers, postal codes, phone fragments. Wrong "verification" code is a tap-to-copy footgun. Only return when labelled regex matched. |
| B-021 | `apps/server/src/trpc/routes/assistant.ts:498-507` | correctness | `extractReceiptDetails` amount regex matches unrelated numbers on noisy receipts. Anchor matches to a "Total/Amount/Charged" label nearby. |
| B-022 | `apps/server/src/trpc/routes/assistant.ts:2255-2354` | performance | Non-conversational threads pay the full `buildThreadAnalysis` cost (LLM/vector/related-task) and then zero out actionable fields. Classify early and short-circuit. |
| B-023 | `apps/server/src/pipelines.ts:622-637` and `795-810` | maintainability | Effect-based and imperative versions reimplement automation-policy fetch + default-fallthrough. Effect version's `Effect.orElse` after a `try` with catch is dead. Extract `getUserAutomationPolicy(userId)`. |
| B-024 | `apps/server/src/lib/ai-profile.ts:124-133` | prompt-injection (low) | `identity.name` / `identity.email` interpolated into system prompt unsanitized. Strip leading `#`, backticks, code fences. |
| B-025 | `apps/server/src/routes/ai.ts:524-542` | cost | 21 KB `GENERATIVE_UI_PROMPT` injected into every system prompt regardless of client capability. Gate by `clientCapabilities`. |
| B-026 | `apps/server/src/trpc/routes/assistant.ts:2759-2778` | consistency | `dismissPreparedAction` lacks `lastReviewedAt: new Date()` and `actionId` shape validation that sibling `dismissOpenLoop` has. |
| B-027 | `apps/server/src/lib/ai-profile.ts:78-87` | correctness (LLM context) | Formatted local time omits timezone designator — same wall-clock string in PST and EDT is ambiguous. Add `timeZoneName: 'short'`. |
| B-028 | `apps/server/src/thread-workflow-utils/workflow-engine.ts:382-385` | design | `vectorizationWorkflow` and `labelGenerationWorkflow` registered unconditionally even when user has disabled assistant automation. Worth a deliberate decision. |
| B-029 | `apps/macos/TodusMac/Views/Email/MacEmailComposeView.swift:497-506` | correctness | Compose autosave `Task` not cancelled on view dismiss; pending 1-second autosave can write after `clearAutosavedDraft()` runs on send. Add `.onDisappear { autosaveTask?.cancel() }`. |
| B-030 | macOS + iOS `EmailService.withTimeout` | performance | `defer { group.cancelAll() }` issues structured cancellation, but unclear if `URLSession.data(for:)` honors `Task.isCancelled` in `TodosAPIClient`. Verify; use `withTaskCancellationHandler` to call `urlTask.cancel()`. |
| B-031 | `apps/macos/TodusMac/Views/Home/MacHomeView.swift:567-577` | dead code | `openMacBriefingRow` thread-id branch and fallback both call `onNavigate?(.email(.inbox))`. Implement deep-link or simplify to single call. |
| B-032 | `apps/macos/TodusMac/Domain/TaskSmartSort.swift:70-76`, `99-114` (and iOS mirror) | consistency | `bucket(for:)` returns single `.noDate`; `score(for:)` splits high-priority no-date from other. Bucket header view groups them together so the split is visually invisible — pick one. |
| B-033 | `apps/ios/Todus/Todus/Features/Tasks/TaskRowView.swift:225` & `apps/macos/TodusMac/Domain/SnoozeOption.swift:38` | UX | `SnoozeOption.weekend` lands on next Saturday when called Saturday afternoon. On Saturday, prefer Sunday 9am. |
| B-034 | `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift:171-176` | edge case | `.onAppear` sets `hideTabBar = false`; no symmetric restore on dismiss. Document or restore previous value. |
| B-035 | `apps/ios/Todus/Todus/Navigation/CreateSheet.swift:880-897` | correctness contract | `CompoundIntentParser` multi-intent path uses `intent.date ?? selectedDate` for every intent; unclear whether explicit folder/date should override every sub-intent. Define contract. |
| B-036 | `apps/ios/Todus/Todus/Navigation/CreateSheet.swift:875` | UX regression? | Auto-resolve type now requires both keyword AND date for `.event`. "Dentist Tuesday 2pm" used to classify as `.event`, now falls through to `.task`. Confirm intentional. |
| B-037 | `apps/ios/Todus/Todus/Services/Email/EmailService.swift:282-287` | observability | Stale-refresh detection uses strict `<`, so equal-newest refresh is accepted. Surface dropped count to telemetry. |
| B-038 | `apps/ios/Todus/Todus/Services/AI/AIChatService.swift` | correctness (rare race) | Comment says "Load deleted IDs synchronously addresses this" but `deleteConversation` mutates `conversations` itself, which the async loader can overwrite. Verify and document. |
| B-039 | `apps/web/app/(routes)/mail/tasks/page.tsx:204` | performance | New `void queryClient.invalidateQueries(...)` runs on every create on top of optimistic cache update — can thrash. Debounce or only invalidate when sort/filter would actually move the inserted task. |
| B-040 | `apps/web/app/(routes)/mail/tasks/page.tsx` | i18n | `NlpQuickAdd` placeholder is hardcoded English with Swedish example — confusing and not localized via Paraglide. |

## Hygiene (do not commit)

| ID | File | Action |
|----|------|--------|
| B-050 | `new-website/dev.log` (untracked), `new-website/relume/dev.log` (modified) | `git rm --cached new-website/relume/dev.log`; add `**/dev.log` to root `.gitignore`. |
| B-051 | `new-website/check-font.js`, `new-website/check-page.js`, `new-website/screenshot.js` (all 0 bytes) | Delete locally; if planned tooling, write content first. |

## Test gaps

| ID | Area | Approach |
|----|------|----------|
| B-060 | iOS + macOS parsers | Unit-test `LocalTaskParsingService`, `TaskSmartSort`, `CompoundIntentParser`. Cover `today 14` regression (B-011), weekday ordering, time rollover, smart-sort bucket assignment. |
| B-061 | apps/server | Unit-test `classifyThreadKind`, `extractVerificationCode`, `extractReceiptDetails`, `buildAiLeadLine`. Pure functions with high false-positive risk. |
| B-062 | iOS + macOS `withTimeout` | Sleep 5s with 0.1s timeout, assert `.timeout` thrown within ~150 ms. |
| B-063 | macOS compose | Smoke test that builds a draft with cc/bcc/connectionId and asserts wire payload (would have caught B-005). |

## Verified clean

- `d8d471c7` server pagination/parser regression fix — composite `(latestReceivedOn, id)` cursor correctly fixes the single-shard "exactly maxResults" pagination dead-end and the equal-timestamp cross-shard tie-skip. Backwards-compatible legacy parser path preserved.
- `apps/ios/Todus/Todus/Services/API/TodosAPIClient.swift` — `serializeJSONValue` correctly addresses NSInvalidArgumentException on `null`/fragment payloads. `EmailEmptyResponse` decodes from `{}` cleanly.
- `packages/swift-auth/Sources/TodusAuth/AuthService.swift` `preloadTokens()` — `nonisolated static` calling thread-safe `KeychainHelper.read` is sound.
- `apps/macos/TodusMac/Views/Email/MacEmailInboxView.swift` polling no longer triggers `forceSync` — fixes the destructive-resync-on-every-poll regression.
- `apps/ios/Todus/Todus/Domain/MailAssistantModels.swift` custom `init(from:)` with backward-compatible decoding for `aiLeadLine`/`threadKind`/`extractedCode`/`extractedReceipt` — correct pattern for staged backend rollout.
- `new-website/relume/{home,download,legal,pricing}/components/Navbar11.jsx` — pure formatting; all four files remain byte-identical post-change. (4-way duplication is its own debt; leaving for now.)
- `apps/web/messages/en.json` — only adds `pages.settings.general.location` keys; consistent with surrounding entries.
- `apps/macos/TodusMac/Views/Calendar/CalendarTimeGridView.swift` 1440-min cap — correct fix for visual overflow.
- `apps/macos/TodusMac/Views/Calendar/MacCalendarView.swift` `calshow:<refInterval>` URL — correct macOS scheme.
- `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift` `inFlightAction` race handling — correctly captures the action and only clears if it hasn't been replaced.

---

## Resolved in 2026-03-31 Review Session

| ID | Title | Area | Type | Status | What Changed |
|----|-------|------|------|--------|-------------|
| F01 | Missing `toast` import in chat/page.tsx | web/chat | bug | auto-fixed | Added `import { toast } from 'sonner'` — was causing runtime error on conversation load failure |
| F02 | Missing `Link` import in calendar/page.tsx | web/calendar | bug | auto-fixed | Added `import { Link } from 'react-router'` — was causing runtime error when calendar rendered |

---

# 2026-05-17 — iOS Bug-Hunt + UX-Polish Audit

Scope: `apps/ios/Todus/` — full read-only audit across 6 surfaces (auth/onboarding, email, tasks, calendar, AI chat, infra/services). 6 parallel sub-agents. No edits applied; user to triage. Total: 68 bugs, 84 polish items.

## Critical (ship-blockers) — 5

| # | File:line | Title | Surface |
|---|-----------|-------|---------|
| C1 | `packages/swift-auth/Sources/TodusAuth/AuthService.swift:877-883` | Deep-link token injection on unauthenticated app — attacker `todus://auth-callback?token=X` accepted when signed out; Apple flow never sets `pendingAuthFlowExpiresAt` | auth |
| C2 | `apps/ios/Todus/Todus/App/TodosApp.swift:411-413` | Notification taps for email/AI/due-task/reminder are dead — switch only handles `TASK_COMPLETE`/`TASK_SNOOZE`, everything else falls into `default: break` | infra |
| C3 | `apps/ios/Todus/Todus/Services/AI/AIChatService.swift:1370-1485` + `Features/AI/AIChatView.swift:217-244` | Mutation confirmation deadlocks AI agent — `send_email`/`update_calendar_event`/`delete_calendar_event` suspend forever; no UI observes `pendingMutationConfirmation` | ai |
| C4 | `apps/ios/Todus/Todus/Services/AI/AIChatService.swift:416-434` | Mutation continuations leak on cancel — `cancelStream` only resumes delete continuations, never mutation ones; Stop mid-confirm leaks Task + CheckedContinuation warning | ai |
| C5 | `apps/ios/Todus/Todus/Features/Calendar/CalendarPermissionView.swift:39` | Calendar permission view stuck loading after grant — no `onReceive(.todusCalendarAuthorizationDidChange)`; view never invalidates | calendar |

## High severity — 17

### Auth (2)
- **H1** `AuthService.swift:1354-1372` — Stale refresh token persisted across re-login; JWT-only third branch never clears `refreshToken`/`currentSessionId` → cross-account session leak
- **H2** `Services/Auth/AuthSessionStore.swift:294-305` + `TodosApp.swift:42,54` — Legacy Supabase store flipped into magic-link state by Better Auth callback URLs containing `email=`

### Email (3)
- **H3** `Features/Email/EmailThreadView.swift:493-501` — Star toggle never rolls back on API failure; user thinks starred, isn't
- **H4** `Features/Email/EmailThreadView.swift:1049-1054` — `markAsSpam` always dismisses regardless of success; offline spam-report silently fails
- **H5** `Features/Email/EmailThreadView.swift:294-321` + `EmailInboxView.swift:600-612` — `priorError \!= current` failure detection fragile across shared singleton state; concurrent ops mask/mimic failures

### Tasks (3)
- **H6** `Features/Tasks/TasksTabView.swift:209-220` — `consumePendingTaskNavigation` uses GCD `asyncAfter` w/ no cancel; rapid second tap shows stale task
- **H7** `Services/Parsing/RemoteFirstTaskParsingService.swift:38-55` — Remote NLP `lowConfidence` silently dropped; only surfaces on local fallback
- **H8** `Services/Tasks/TaskCaptureService.swift:100-129` — Capture rollback races concurrent enrichment enqueues; non-deterministic state machine

### Calendar (3)
- **H9** `Features/Calendar/CalendarTabView.swift:448, 456` — Day view shows ONLY Apple events; Google events stripped because `loadEvents` early-returns for `.day` mode
- **H10** `Features/Calendar/CalendarTabView.swift:520-524` — Tapping Google/CalDAV event silently no-ops; `event(withIdentifier:)` returns nil and code `return`s
- **H11** `Features/Calendar/EKWrapper.swift:46-50` — Force-unwrap on `ekEvent.calendar.cgColor` crashes when calendar deleted mid-session

### AI (3)
- **H12** `Services/AI/AIChatService.swift:1910-1929` — `flushTokenBuffer` runs against stale messageID; mid-flush `clearHistory`/`retry` loses tokens
- **H13** `Services/AI/AIChatService.swift:2192-2196` — Calendar snapshot leaks "not granted" string after permission grant until cache invalidated
- **H14** `Services/AI/AIChatService.swift:1066-1078` — SSE byte parser splits on `\n` only; `\r\n` from CDN causes `"[DONE]\r"` mismatch + decode failures on final chunk

### Infra (3)
- **H15** `Services/API/TodosAPIClient.swift:163-189` — TRPC body sent as raw JSON; server superjson expects `{json,meta}` for `Date`/`Set`/`BigInt` — dates corrupt over wire
- **H16** `Services/API/TodosAPIClient.swift:60-64` — `JSONSerialization.data(withJSONObject:)` crashes on String/Int inputs (fragment rule); `trpcBatchQuery` with id arrays raises NSInvalidArgumentException
- **H17** `Services/Voice/AudioPlayerManager.swift:68-82` — `ensureEngineRunning` re-attaches already-attached node when session ends without `stop()`; crashes on reconnect

## Medium severity — 46

(Full per-surface lists archived in agent transcripts; high-leverage subset listed below)

### Email
- `EmailThreadView.swift:866` markAsRead failure poisons shared `errorMessage` → contaminates subsequent dismiss checks
- `EmailComposeView.swift:691-695` `canSend` blocks legitimate empty-subject replies
- `EmailRowView.swift:10-15` `timeString` cached in init → "Yesterday" stale across midnight
- `Services/Email/EmailService.swift:309-313` pagination dedupe by id only; stale page-1 thread retained when newer copy lands on page 2
- `EmailInboxView.swift:1269-1276` `consumePendingThreadNavigation` GCD asyncAfter fires after view disappears
- `EmailInboxView.swift:306-308` `badgeForciblyHidden` latches across refreshes
- `EmailComposeView.swift:94` Reply/ReplyAll separate autosave keys orphan drafts
- `EmailThreadView.swift:1786+` EmailHTMLView no nav delegate → in-place link nav strands user

### Tasks
- `Services/Reminders/AppleRemindersSyncService.swift:340-358` `inFlightUpserts` guard is no-op; redundant EKEventStore XPC calls
- `Services/Reminders/AppleRemindersSyncService.swift:340-357` Two-way sync never reopens — uncheck in Reminders, Todus stays done
- `Features/Tasks/InboxView.swift:128` `onChange(of: allTasks)` walks N items on every SwiftData mutation
- `Services/Tasks/TaskCaptureService.swift:98` `try? context.save()` swallows disk-full errors
- `Services/Tasks/TaskCaptureService.swift:65-66` No cap on `splitInputLines`; 10k-line paste = 10k enrichment tasks
- `Services/Reminders/AppleRemindersSyncService.swift:301-310` `pendingUpsertTaskIDs` retry recursive, no max-attempts

### Calendar
- `Features/Calendar/CalendarTimeGridView.swift:19, 67-69` `Timer.publish(...).autoconnect()` leaks per page in MultiDay
- `Features/Calendar/CalendarViewController.swift:140-172` `fetchEvents` ignores authorization revoke; stale events served forever
- `Features/Calendar/CalendarTabView.swift:483-485` `isLoading` not reset on Task cancellation
- `Features/Calendar/CalendarTabView.swift:204` `.highPriorityGesture(pinch)` conflicts with `UIPageViewController` swipe
- `Services/Meetings/MeetingsService.swift:140-146` `syncFromCalendar` only `print`s errors

### AI
- `Services/AI/AIChatService.swift:1107-1116, 2528-2534` Keep-alive deltas treated as `.unrecognised` → main-actor JSON decode spam
- `Services/AI/AIChatService.swift:2002-2007` 50-conversation history serialized into one Keychain blob → exceeds ~4KB item limit; silent persist failure
- `Services/AI/AIChatService.swift:1119-1132` Stale `streamFailed` not reset on cancel; retry banner from prior turn sticks
- `Services/AI/AIChatService.swift:1727-1734` `buildPayload` includes in-flight assistant placeholder content → duplicated assistant turn in next step
- `Services/AI/AIChatService.swift:346-393` `retry(...)` doesn't clear `messages[i].errorMessage` → footer pinned under successful response
- `Services/AI/AIChatService.swift:2070-2104` `fetchFullConversation` overwrites local renames/moves unconditionally

### Infra
- `Services/Subscription/SubscriptionService.swift:100-104` `cancel` re-entrancy on shared `isLoading`; spinner deadlock on double-tap
- `Services/Notifications/NotificationDigestService.swift:173-211` Hand-rolled URLSession bypasses TodosAPIClient — no 401 refresh, no superjson
- `Services/NetworkMonitor.swift:9, 16` `isConnected` defaults `true` pre-NWPath callback → wrong banner flash, false reconnect trigger
- `Services/Widgets/WidgetUpdateManager.swift:40-50` Tasks completed today without `dueDate` excluded from widget stats
- `Navigation/MainTabView.swift:86-101` Calendar permission desync — Settings flip without scenePhase change shows stale permission UI
- `Navigation/CreateSheet.swift:973-1011` Event create allows end < start; backend rejects, user loses transient state
- `DesignSystem/AppTheme.swift:14-17` Avatar cache `dataKey = urlString.hashValue` — non-stable across launches (process-salted), cross-user collision risk
- `DesignSystem/AppTheme.swift:36-48` Avatar JPEG bytes in UserDefaults → bloats prefs.plist, slows launch
- `DesignSystem/AppTheme.swift:530-543` `AppPrimaryButtonStyle` hardcodes `Color.blue` — ignores `Color.accentColor` / Increase Contrast

### Auth (additional)
- `AuthService.swift:228-358` Apple Sign In never sets `pendingAuthFlowExpiresAt` → provenance bypass + mid-flow URL kills state
- `App/RootView.swift:85-88, 105-108` `loadSharedAIProfile` called twice on signed-in launch
- `KeychainHelper.swift:38-43` Legacy-delete failure aborts save → silent token drop on locked keychain

## UX polish — top 20 across surfaces (84 total in agent transcripts)

| # | Impact | File:line | Gap | Fix |
|---|--------|-----------|-----|-----|
| P1 | High | `Features/Email/EmailInboxView.swift:635-648` | Archive uses `role: .destructive` (red) — fear of mis-swipe | Drop `.destructive` |
| P2 | High | `Features/AI/AIChatView.swift:1332-1342` | Send button disappears when empty → layout shift | Always render, gate `.disabled(isEmpty)` |
| P3 | High | `Features/AI/AIChatView.swift:914-919` | "Thinking…" vanishes on first token but text may be empty for 10s if reasoning tokens stream | Keep indicator while `reasoningContent` grows + `content` empty |
| P4 | High | `Features/AI/AIChatView.swift:2247-2273` | Thumbs up/down is local-only no-op → fake feedback | Wire to feedback endpoint or remove |
| P5 | High | `Features/Tasks/TaskRowView.swift:286` | No haptic on complete | `UIImpactFeedbackGenerator(.light).impactOccurred()` |
| P6 | High | `Features/Tasks/TaskRowView.swift:112-117` | Context-menu Delete no confirmation (TaskTableView has one) | Add `confirmationDialog` |
| P7 | High | `Features/Calendar/CalendarTimeGridView.swift:155-160` | Event blocks <24pt below 44pt HIG touch target | `.frame(minHeight: 44)` on contentShape |
| P8 | High | `App/GmailOnboardingView.swift:51-84` | Skip stays tappable during connect → race | `.disabled(isConnecting)` |
| P9 | High | `Features/Email/EmailThreadView.swift:493-501` | Star button no accessibility state | `.accessibilityLabel(isStarred ? "Starred" : "Not starred")` |
| P10 | High | `Navigation/MainTabView.swift:296-308` | Offline banner subtle pill, no retry CTA | Add Retry button |
| P11 | High | `Features/Email/EmailComposeView.swift:201-231` | Send button no "Sending…" text, no success haptic | Add label + `.sensoryFeedback(.success, trigger:dismissed)` |
| P12 | High | `Features/Auth/AuthView.swift:144-165` | Apple/Google tappable while Email OTP loading | `.disabled(authService.isLoading)` on stage-1 stack |
| P13 | High | `Features/Auth/AuthView.swift:73-76` | Error banner persists indefinitely | Auto-clear via `.task(id: lastErrorMessage)` |
| P14 | High | `Features/Home/HomeView.swift:1054-1067` | No skeleton on cold launch — white 1-3s | 3 ghost rows while `\!hasLoadedEmailState` |
| P15 | High | `Features/Calendar/CalendarListView.swift:170-180` | Empty calendar dead-ends — no CTA | Add "Create event" button |
| P16 | Med | `Features/Tasks/BoardColumnView.swift:78-83` | Empty board column no `+` (drop-only on touch) | Add `+` to column header |
| P17 | Med | `Features/Calendar/CalendarEventBlockView.swift:18-48` | No VoiceOver label | `.accessibilityLabel("\(title), \(timeString)")` |
| P18 | Med | `App/NotificationsOnboardingView.swift:90-99` | Skip tappable during permission request | `.disabled(isRequesting)` |
| P19 | Med | `Features/AI/AIChatService.swift:1521` | `appendFallback` writes literal "Done." | Generate from chip set |
| P20 | Med | `Features/Email/EmailThreadView.swift:1564` | Timestamp uses abbreviated date for recent — "2 min ago" expected | `RelativeDateTimeFormatter` <24h |

## Recommended fix order

1. **Today (security/data loss):** C1, H1 (auth token leaks); C2 (notification deep-links dead); C3+C4 (AI mutation deadlock+leak).
2. **This week (user-visible silent failures):** C5, H3, H4, H5 (email silent failures); H9, H10, H11 (calendar Day view + crashes); H15, H16 (TRPC wire format).
3. **Next sprint (data integrity):** H2, H6, H7, H8, H12, H17 + medium-severity sync/persistence items.
4. **Polish backlog:** Top-20 polish list — most are ≤5 line changes, batch into a single PR.

Full per-agent transcripts available at task IDs af528b40, ac4cfe8a, a5957fb7, a1675c0e, a8be1ed8, ad5e823b.

---

# 2026-05-20 — iOS Mobile App Bug Hunt

Scope: main user flows (auth, email, AI chat, tasks, calendar, network) in `apps/ios/Todus/Todus/`. 6 parallel investigators reviewed services + feature views. Findings below have been *verified by reading the cited line ranges* — speculative investigator claims that did not survive verification are listed separately at the bottom so they don't get re-investigated.

## Auto-fixed in this run

| ID | File:line | Status | What changed |
|----|-----------|--------|--------------|
| BH-2026-05-20-01 | `apps/ios/Todus/Todus/Services/AI/AIChatService.swift:2066` | fixed | `finaliseStream` set `isStreaming = false` *before* flushing `tokenBuffer` into the message. SwiftUI subscribers that read both flags could see the typing indicator disappear while the last tokens were still being appended. Moved the flag reset after the flush + `parseUISpec()`. |
| BH-2026-05-20-02 | `apps/ios/Todus/Todus/Services/Tasks/SupabaseSyncService.swift:42` | fixed | `enqueue()` on the `client == nil` path called `queue.popLast()?.continuation.resume()` *and then* `continuation.resume()`. The popped batch's continuation **is** the outer `continuation` (just appended one line above), so this double-resumed a `CheckedContinuation`, which traps with a fatal error. Replaced pop-then-resume with `queue.removeLast(); continuation.resume()`. |

## Verified — needs human review

| ID | File:line | Severity | Issue | Suggested fix |
|----|-----------|----------|-------|---------------|
| BH-2026-05-20-03 | `apps/ios/Todus/Todus/Features/Email/EmailAIDraftSheet.swift:257` | warning | `defer { Task { @MainActor in isStreaming = false } }` inside the outer `Task` schedules a *detached* hop to reset the flag. The outer `streamingTask` returns before the flag is reset, so a fast user can re-tap "Generate" while `isStreaming` is still true momentarily, or dismiss the sheet and have the detached Task mutate freed view state. | Replace the detached `Task` with an `await MainActor.run { isStreaming = false }` at the end of the outer Task body, or set the flag before the `defer` exits via direct assignment (the outer Task is already `@MainActor`-isolated via the enclosing view). |
| BH-2026-05-20-04 | `apps/ios/Todus/Todus/Services/Reminders/AppleRemindersSyncService.swift:286` | info | `completionDate = task.completed ? task.updatedAt : nil`. If a task was completed long after its last edit (e.g. updated at 9am, completed at 5pm), `completionDate` is set to the *edit* time, not the *completion* time. Surfaces in Reminders' "Completed" smart list with the wrong timestamp. | Track `completedAt` separately on `TaskRecord` and write that into Reminders, or write `.now` on the transition `false → true`. Skipped auto-fix because the model change is non-trivial. |

## Unverified leads (investigator candidates that need a closer look)

These were flagged by the parallel investigators but could not be confirmed without deeper context. They are listed so future passes can either confirm or close them.

- `apps/ios/Todus/Todus/Services/AI/AIChatService.swift` — claims of (a) partial JSON in tool arguments after `[DONE]` (line ~1115), (b) `executeToolCalls` not honouring cancellation between awaits (line ~1214), and (c) `syncLoadConversations` racing with local deletes (line ~2233). All plausible but require running the SSE parser and the delete handler concurrently to confirm.
- `apps/ios/Todus/Todus/Services/Tasks/SupabaseSyncService.swift:45` — claim that `queue.popLast()` races with concurrent `enqueue()`. Service is `@MainActor` so concurrent calls serialise, *but* the inner `Task { await processQueue }` re-enters the actor between awaits — worth re-reading once we add a `processQueue` test fixture.
- `apps/ios/Todus/Todus/Services/Reminders/AppleRemindersSyncService.swift:359` — off-by-one in `maxCoalescedRetries` (allows N+1 attempts). Need to read the retry counter increment vs guard to confirm.
- `apps/ios/Todus/Todus/Features/Calendar/CalendarTimeGridView.swift:295` — multi-day event height collapse when `rawEndMinutes` is capped at 1440 without recalculating duration on subsequent days. Reproduce with a 2-day event spanning midnight.
- `apps/ios/Todus/Todus/Features/Calendar/CalendarMultiDayView.swift:346` — claim that `startOfDay(for: event.startDate)` vs `startOfDay(for: date)` mismatch causes all-day events to render on the wrong day across DST/timezone boundaries.
- `apps/ios/Todus/Todus/Services/Calendar/GoogleCalendarService.swift:316–333` — `fetchCalendars(for:)` catches errors and returns `[]` while clearing `scopeMissing`. Conflates "no scope" with "network failure". UI gives no retry banner.

## Speculative claims dismissed during verification

(Listed so the next bug hunt doesn't re-flag them.)

- ~~`AuthView.swift:142` — `if case .otpPending(let email)` pattern allegedly broken.~~ Verified valid Swift; `otpPendingEmail` works correctly.
- ~~`TodosAPIClient.swift:231` — TRPC envelope decode `try?` "swallows" errors.~~ Documented intentional fallback to bare-response decoding (see comment at line 239).
- ~~`TodosAPIClient.swift:345` — bearer token nil header.~~ Code already uses `if let token` guard; header only set when token exists.
- ~~`TodosAPIClient.swift:376–383` — 401 retry "broken".~~ `didRefresh` flag intentionally limits refresh to one attempt per request, then surfaces `unauthorized`. Behaviour matches the inline comment.
- ~~`TodosAPIClient.swift:404–413` — mutation retries unsafe.~~ Retry list is explicitly restricted to URLErrors that mean "request did not reach the server"; matches the inline comment.
- ~~`CalendarService.swift:96–124` — empty `hiddenCalendarIds` "returns everything".~~ Documented as legacy behaviour in the doc comment ("An empty set fetches across all calendars").
- ~~`UnifiedCalendarService.swift:82–93` — Apple/Google tasks "throw and silently lose Apple data".~~ Neither helper is `throws`; the `async let` returns `[]` on failure.
- ~~`EmailInboxView.swift:627` — pagination success misdetected as failure.~~ Logic correctly checks `if let current` *and* `current \!= priorError`; nil case is handled.


## Bug Hunt — 2026-05-21

### Auto-fixed (3 issues)
- `apps/macos/TodusMac/App/MacAppServices.swift` — moved the dynamic settings-save encoder out of a generic function so Swift 6 can compile `syncSetting`.
- `apps/macos/TodusMac/Views/Home/MacHomeView.swift` — fixed the misplaced enclosing brace around the nested hover row helper.
- `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift` — split large SwiftUI modifier chains into smaller helper chains to resolve compiler type-check timeouts.

### Needs human review (0 issues)
- None.

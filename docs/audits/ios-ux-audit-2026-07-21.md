# iOS UX audit — Todus (2026-07-21)

> **Remediation addendum (same day, later session):** 24 of 25 findings fixed on `ios/perf-stability-tasks-density` (TD-23 dead-file deletion deferred — removal declined; TD-17 tour hierarchy deliberately left for real-user evidence). Build succeeded. Simulator re-verification: TD-01 (no guest banner), TD-02 (text scales at AX-XL: header 17→39pt, row 78→159pt), TD-04 (draft survives scrim dismiss), TD-05 (no permission prompt on capture), TD-24 (Settings in More), calendar timeline renders after the now-line refactor. Network-path fixes (TD-03/06/07/08/09/10/19/21) are code-verified only — they need a real-account device pass. Plus backlog perf items PERF-2/3/4 fixed. Details: CHANGELOG.md [Unreleased] 2026-07-21 entry. Updated launch verdict: **small external test = Yes** (conditions met); **App Store = Yes, with conditions** — deploy the idempotent-send backend first (TASK.md Task 5) and run one real-account device smoke test (attachments, send, archive-undo, Reminders sync).

Audit-only. No production code was modified. Branch under audit: `ios/perf-stability-tasks-density` (HEAD `2170e55a`).

Method: repo/product-doc review, four parallel workstreams (product model, simulator journey testing, SwiftUI robustness code audit, accessibility + native-convention code audit), reconciled and deduplicated by the lead auditor. Simulator: iPhone 17 Pro + iPhone SE 3rd gen, iOS 26.4, seeded UI-testing sessions (`--ui-testing`, `--ui-testing-fresh-install`) because no real Gmail-connected account was available in this environment.

---

## 1. Executive roast

Todus is trying to replace Mail + Reminders + Calendar with one calm workspace, with an AI layer doing the connecting. The surprising verdict: **the core skeleton is genuinely good.** Onboarding is honest and skippable, the capture loop ("Call dentist tomorrow at 3pm" → parsed task, offline, in ~4 seconds) actually delivers the pitch, failure states mostly exist, and the codebase shows evidence of repeated hardening passes (idempotent send, generation-gated loads, persisted delete tombstones). This is not a demo app wearing a product costume.

What undermines it is a **trust layer that lies at the edges**:

- A brand-new guest user's first screen carries a persistent orange **"Session expired — Sign in again"** banner. They never had a session. It also visually collides with the nav title and toolbar. First impression: the app is broken.
- The remedy that banner (and the AI chat's 401 error copy) prescribes — sign out and back in — **permanently deletes any tasks captured offline that never reached the server.** The app tells users to pull the trigger on its own data-loss path.
- **Dynamic Type is effectively unsupported** (924 fixed-size fonts, 2 `@ScaledMetric` uses). Simulator-verified: at accessibility XL, no text changes size; only the FAB circles balloon. For an accessibility-size user this app is exclusionary.

Who succeeds: a sighted, default-text-size, Gmail-using enthusiast who signs in with Google on day one. Who struggles: guests, Apple-sign-in users (extra Gmail step + broken-looking banner), anyone with large text, VoiceOver users in AI chat / thread toolbars.

Strongest part: the quick-capture loop and the onboarding chain. Most serious problem: the session/trust edge cases above. Ready for internal testing: yes. Ready for App Store: not yet — the P1s below are fixable in days, not weeks.

---

## 2. Product and user model

- **Intended user** (inference from PRD §1): professionals living in email + calendar + tasks who want one app; Gmail-only mail; iPhone-first early adopters.
- **User problem:** context switching and re-entry across three system apps; commitments fragmented.
- **Primary job:** process the day from one app — know what's next (Home), capture commitments frictionlessly (FAB), handle email/calendar without leaving.
- **Supporting jobs:** offline-first tasks + Apple Reminders sync; AI chat/voice as navigator and mutator; meetings summaries; docs; cross-platform continuity (web/macOS).
- **Alternatives:** Apple Mail+Calendar+Reminders (free, default), Gmail+Google Calendar+Tasks, Spark/Superhuman, Todoist/Things, Notion Mail/Motion.
- **Assumptions:** single-account Gmail; portrait iPhone use.
- **Unclear product decisions:** 6 content tabs squeezed into 4 slots + More (PRD says "four lenses"); Gmail-only with no in-app explanation; "Auto" AI routing of captures is opaque; Docs on iOS is a thin WebView of the web product; credits displayed at 10× internal value.
- **App facts:** min iOS 18.0, iPhone+iPad device families but **portrait-only** (odd combination for iPad), tabs user-customizable (max 4) + fixed More, auth = Apple / Google / Email OTP / guest, deep links `todus://` (auth, share, mailto only).

## 3. Core-journey scorecard (1–5)

| Journey | Score | Evidence |
|---|---|---|
| First-launch comprehension | 5 | Startup card states the value prop in one line; two clear CTAs (sim, `j1-01`) |
| Onboarding | 4 | 3 steps, honest skip copy, progress pill, context-first permission explainers; −1 for truncated strings and inverted "Skip tour" primary button |
| Time to first value | 4 | Guest → captured NLP-parsed task in <90s; −1 because the false "Session expired" banner poisons the same first session |
| Primary task completion (capture) | 5 | "Call dentist tomorrow at 3pm" → title + 22 Jul 15:00 due, offline, toast confirmation (sim-verified) |
| Returning-user orientation | 4 | Relaunch: greeting, This Week with the task under "Tomorrow", adaptive setup checklist; state survives kill |
| Navigation | 4 | Native TabView, labels, preserved tab state, More tab with clear customization copy; Settings only behind avatar (discoverability) |
| Input & forms | 3 | Create sheet excellent; but scrim tap silently discards typed text; AI profile fields save only via "Done" (code) |
| Feedback & save confidence | 3 | Toasts + haptics good; but false session banner, notification-action completions that never sync (code), silent enrichment title clobber (code) |
| Errors & recovery | 3 | Mail list has honest "Still checking… Try Again"; AI chat failure preserves input with retry; −: copy blames connection on auth errors, 401 copy prescribes destructive sign-out |
| Accessibility | 1 | Dynamic Type dead (sim-verified); zero Reduce Motion support; unlabeled icon buttons in AI/thread/Home; VO-invisible tap rows |
| Mobile layout | 4 | SE (375pt) shows no clipping (AX-frame sweep); dark mode intentional; sub-44pt "Open/View all/Manage" links on Home |
| Performance | 4 | No hitches observed in tested flows on 17 Pro; known deferred perf items documented in backlog |
| Trust | 2 | Privacy consent before first AI call is excellent; but false-expired banner + "log out" advice that deletes data + settings silent revert |
| Retention value | 3 | Capture+Reminders sync is a real daily hook; email is the value anchor but untestable here without a real account |

## 4. Launch verdict

| Level | Verdict | Blockers / conditions |
|---|---|---|
| Internal testing | **Yes** | None — current state is fine for the founder/dogfooding |
| Small external test (5–20 friendly users) | **Yes, with conditions** | Fix TD-01 (guest/expired banner) and TD-03 (sign-out data wipe warning) first; both are small |
| Private beta (TestFlight, ~100) | **No → Yes after** | TD-01…TD-05 + deploy the idempotent-send server (TASK.md Task 5) so send-retry isn't inert |
| App Store submission | **No** | All of the above + TD-02 Dynamic Type remediation of top list/row/detail screens + Reduce Motion gate (App Review a11y risk + real user harm) |
| Public launch | **No** | Above + real-user validation of email happy path, retention, and AI value (see §13) |

## 5. Highest-priority findings

| ID | Sev | Finding | User impact | Evidence | Smallest useful fix |
|---|---|---|---|---|---|
| TD-01 | P1 | Fresh guest sees persistent "Session expired — Sign in again" banner; overlaps nav title/buttons | First-session trust destroyed; instructs pointless re-auth | Verified in simulator (`j1-08`); `MainTabView.swift:87`, `isSessionExpired` set by 401s guest calls inevitably hit | Never set `isSessionExpired` for guest/no-session; suppress mail API calls for guests; give banner a safe-area slot |
| TD-02 | P1 | Dynamic Type unsupported app-wide (924 fixed fonts, 2 `@ScaledMetric`) | Large-text/AX users get zero scaling — core journeys illegible | Verified in simulator (AX-XL screenshot: no text scaled, FAB circles ballooned); grep counts | Typography tokens via `relativeTo:`; migrate TaskRowView, EmailRowView, HomeView, AIChatView, EmailThreadView first |
| TD-03 | P2 | Sign-out (incl. "Sign In Again" path) deletes offline-captured `.localOnly` tasks without warning | Permanent data loss triggered by UI's own advice | Code-confirmed `AppServices.swift:897-906` + banner/AI copy paths | Count `.localOnly/.failed` tasks before wipe → warn, or final flush attempt |
| TD-04 | P2 | Create-sheet scrim tap silently discards typed text | Capture lost mid-thought; no confirm, no draft | Verified in simulator (typed text → scrim tap → gone) | Keep draft text in sheet state for the session, or confirm discard when non-empty |
| TD-05 | P2 | System notification permission prompt fires on first task creation, seconds after user chose "Skip, decide later" | Feels ignored; likely permanent denial | Verified in simulator (`j3-06`) | Gate reminder scheduling on prior authorization; re-ask contextually with pre-prompt |
| TD-06 | P2 | Lock-screen "Complete" action writes done locally but never syncs (no `syncState`, no Reminders upsert) | Task done on phone, open forever on web/macOS/Reminders; can revert | Code-confirmed `TodosApp.swift:456-477` vs `TaskCaptureService.setStatus` | Route through `captureService.setStatus` |
| TD-07 | P2 | 60s inbox poll + foreground refresh drop the active search query | Search results silently vanish while query still shown | Code-confirmed `EmailInboxView.swift:278-299` (missing `query:`) | Pass `query:`/skip poll while searching |
| TD-08 | P2 | AI enrichment unconditionally overwrites title after capture — clobbers a user's immediate manual rename | Rename reverts seconds later, also pushed to server | Code-confirmed `TaskCaptureService.swift:647` | Guard on `parseState == .pending` |
| TD-09 | P2 | Folder mutation queue is memory-only: offline folder edits die on kill; deleted folders resurrect | Ghost/undeletable folders across devices | Code-confirmed `FolderSyncService.swift:39` vs persisted task tombstones | Persist queue to UserDefaults like `pendingDeleteRetries` |
| TD-10 | P2 | AI profile settings save only on "Done"; swipe-dismiss edits silently revert on next server load | Classic silent revert of user-entered text | Code-confirmed `SettingsView.swift:98-111`, `AppServices.swift:973-975` | Save in `onDismiss` / debounce-save |
| TD-11 | P2 | Zero Reduce Motion support; ~7 repeat-forever animations incl. every pending task row | Vestibular-sensitive users can't opt out | Code-confirmed (no `accessibilityReduceMotion` in target) | Env-gate the repeatForever sites |
| TD-12 | P2 | VO-invisible tap targets: `onTapGesture` rows (InboxView row toggles completion), unlabeled icon buttons in AIChatView/EmailThreadView/HomeView | VoiceOver users can't operate or get raw SF Symbol names | Code-confirmed `InboxView.swift:403`, AIChatView :503/:749/:1331/:1515 etc. | Convert to Buttons + one labeling pass (~30 lines) |
| TD-13 | P2 | Cached SwiftData model arrays rendered before digest recompute — deleted-model access window on bulk clear | Occasional crash/ghost rows on "clear completed" | Strong inference `InboxView.swift:30-41,137,325-357` | Filter `isDeleted` in render |
| TD-14 | P2 | `mutedText` ≈39% effective opacity used 217×, often at 11–13pt | Metadata illegible for low-vision users; AA-failure risk | Code-confirmed `AppTheme.swift:206-207` | Raise token to plain `.secondary` |
| TD-15 | P3 | AI chat 401 copy: "Session expired. Please log out and back in. (HTTP 401)" | Jargon + prescribes the TD-03 data-loss path | Verified in simulator (`j7-05`) | Human copy + in-place re-auth; never advise sign-out |

## 6. Detailed findings

### [TD-01] Guest users are told their session expired on first launch
- **Category:** Trust / Bug — **Severity:** P1 — **Evidence:** Verified in simulator
- **Journey:** First-time user (guest path) — **Goal:** see what the app is
- **Start state:** fresh install (`--ui-testing-fresh-install`), "Continue as guest"
- **Repro:** Startup → Get started → Continue as guest → skip 3 onboarding steps → MainTabView
- **Expected:** clean Home with setup checklist
- **Actual:** persistent orange "Session expired — Sign in again" banner within seconds; banner overlays the "Home" title and partially covers search/notification buttons (screenshots `j1-08`, `j3-08`)
- **Impact:** every guest; first impression is "broken app"; tapping the CTA leads to auth they explicitly skipped — and to TD-03's wipe path
- **Root cause:** guest mode still fires authenticated mail/API calls; 401 sets `authService.isSessionExpired` (`MainTabView.swift:87`), which was designed for genuinely expired accounts. Banner is placed in a top `safeAreaInset`/overlay that doesn't reserve space from the nav row.
- **Fix:** treat guest as "no session" (never expired); suppress remote mail bootstrap for guests; lay banner out below the toolbar. **Verify:** fresh guest run shows no banner; expired real session still shows it. **Regression risk:** low.

### [TD-02] Dynamic Type does nothing
- **Category:** Accessibility — **Severity:** P1 — **Evidence:** Verified in simulator + code-confirmed
- **Repro:** `simctl ui … content_size accessibility-extra-large` → Tasks tab
- **Actual:** no text anywhere changes size (title rows, chips, headers, search, tab labels); only the two FABs scale (their `@ScaledMetric fabSize`) while their glyphs stay small — giant empty circles over unscaled 16pt text (screenshot `j10-02`)
- **Code:** 924 `.font(.system(size:))` vs 174 semantic fonts; 2 `@ScaledMetric` total; 9–11pt chip fonts in `TaskRowView.swift:307-346`
- **Impact:** every large-text user (~25% of iPhone users bump size; 100% of AX-size users); core journeys illegible; App Review risk
- **Fix:** AppTheme typography tokens with `Font.system(size:, relativeTo:)`; migrate the five highest-traffic row/detail files first; add a floor for 9pt chips. **Verify:** AX-XL screenshot diff. **Regression risk:** medium (layout at AX sizes needs a pass).

### [TD-03] Sign-out deletes unsynced offline tasks — and the UI recommends sign-out
- **Category:** Bug / Trust (data loss) — **Severity:** P2 (P1 if guest banner remains) — **Evidence:** Code-confirmed
- `AppServices.signOut()` → `wipeLocalAccountData()` deletes all TaskRecords (`AppServices.swift:897-906`); comment claims cache "is not authoritative", but `.localOnly` tasks (captured offline, deliberately preserved by `SupabaseSyncService.swift:196-215`) exist only on device. The session-expired banner ("Sign in again", `MainTabView.swift:556-558`) and AI chat 401 copy both push users toward this path.
- **Failure:** capture tasks offline → session expires → follow the banner → those tasks are gone silently.
- **Fix:** before wipe, count `.localOnly`/`.failed`/`.pendingUpload` rows; if >0 warn ("2 tasks haven't synced yet") or flush first. **Verify:** unit test on signOut with a `.localOnly` row. **Risk:** low.

### [TD-04] Create sheet discards typed text on scrim tap
- **Category:** UX (input loss) — **Severity:** P2 — **Evidence:** Verified in simulator
- Typed "Call dentist tomorrow at 3pm", tapped the dimmed area above the composer → sheet closed, text gone; reopening shows an empty field. `CreateSheet.swift:91` scrim `.onTapGesture { close() }` with no draft retention or confirm. (Also a VO problem — see TD-12/a11y §8.)
- **Fix:** retain draft text for the session (cheapest), or confirm discard when input non-empty. **Verify:** type → scrim tap → reopen shows text. **Risk:** low.

### [TD-05] Notification permission prompt ignores the user's explicit "skip"
- **Category:** UX / Trust — **Severity:** P2 — **Evidence:** Verified in simulator
- Onboarding step 2 offers rich context and "Skip, decide later" (good). But the first task creation immediately triggers the system notification dialog (task-reminder scheduling path), interrupting the success moment and burning the one-shot system prompt right after the user said "not now".
- **Fix:** only schedule reminders (and thus prompt) if status is `.authorized`/`.notDetermined`+user-initiated; otherwise defer with an in-app pre-prompt at a natural moment ("Want a reminder 1h before this is due?"). **Verify:** fresh install, skip, create task → no system dialog. **Risk:** low.

### [TD-06] Lock-screen "Complete" never syncs
As table. The handler (`TodosApp.swift:456-477`) sets `completed/status/updatedAt` and saves, bypassing `TaskCaptureService.setStatus` (`TaskCaptureService.swift:225-238`) — so no `syncState = .pendingUpload`, no server enqueue, no Reminders upsert, and `retryUnsyncedTasks` will never pick it up. Phone says done; web/macOS/Reminders say open; a later server pull can resurrect it locally. Fix is a one-line reroute.

### [TD-07] Background/poll refresh silently destroys search results
`EmailInboxView.swift:278-283` (60s poll) and `:293-299` (scenePhase foreground) call `loadThreads` without `query:` while every other path passes it. Because `loadedQuery != nil` breaks `isSameContext`, the unfiltered first page **replaces** server-side search results (`EmailService.swift:364-370`) while the search field still shows the query. User story: search all mail → background the app to copy something → return → most results vanished. Fix: pass the query / skip the poll while searching.

### [TD-08] AI enrichment reverts manual renames
`TaskCaptureService.swift:647` writes `task.title = parsed.title` unconditionally seconds after capture; `dueDate` has a "user set it" guard, title doesn't (despite `updateTitle` setting `parseState = .parsed`). Rename a fresh capture → watch it snap back. Guard on `parseState == .pending`.

### [TD-09] Folder offline edits die with the process; deleted folders resurrect
`FolderSyncService.swift:39` queue is in-memory only (tasks got persisted tombstones in `SupabaseSyncService.swift:27-49`; folders didn't). Offline delete + app kill → `syncSharedFolders` re-inserts the folder next launch. Offline create/rename + kill → local-forever folder the server never learns about. Persist the mutation queue (Codable) like the task tombstones.

### [TD-10] Settings sheet: swipe-dismiss loses AI profile edits
Save happens only in the "Done" button (`SettingsView.swift:98-100`); the sheet has detents + drag indicator, so swipe-down is first-class. Locally the UserDefaults didSet persists — but `loadSharedAIProfile()` (`AppServices.swift:973-975`, run on auth flip and each settings open) overwrites with the stale server copy, and `saveSharedAIProfile` failures are log-only. Net effect: typed "context about you" reverts. Save in `onDismiss`.

### [TD-11] Reduce Motion: zero support
No `accessibilityReduceMotion` reads in the target; repeat-forever animations at `AIChatView.swift:2732/:2993/:3027`, `VoiceChatModalView.swift:264`, `NotificationCenterView.swift:293`, plus repeating `symbolEffect(.pulse)` on every pending task row (`TaskRowView.swift:53`, `OrganizeReviewSheet.swift:76`). Gate them.

### [TD-12] VoiceOver-invisible controls
- Rows activated via bare `.onTapGesture` with no button trait: worst is `InboxView.swift:403` where the tap **toggles completion** silently; also `TaskTableView.swift:226`, `EmailInboxView.swift:1682`, `LocalModelsView.swift:68-96`, `CalendarMonthView.swift:232`.
- Unlabeled icon-only buttons concentrated in AIChatView (9/33 labeled), EmailThreadView (9/18), HomeView (5/12).
- CreateSheet overlay is not modal to VO (`CreateSheet.swift:91` + `MainTabView.swift:218`): no `.isModal`, no `.accessibilityAction(.escape)`, background not hidden.
- Toasts/banners are never announced (no announcement posts anywhere) — "Task added to Inbox" and capture-failure rollbacks are silent to VO (`ToastOverlay.swift:52-119`).
One labeling+traits pass over these files fixes the bulk.

### [TD-13] Stale SwiftData cache window on bulk delete
`InboxView` renders cached `[TaskRecord]` arrays (`:30-41`) whose recompute is deferred to `onChange(of: tasksChangeDigest)` (`:137`); a bulk "clear completed" saves deletions and the intermediate body pass can touch deleted `PersistentModel`s — a known iOS 18 SwiftData crash vector. Strong inference (sequencing code-confirmed, faulting behavior runtime-dependent). Filter `task.isDeleted` when rendering.

### [TD-14] `mutedText` token is ~39% effective opacity
`AppTheme.swift:206-207`: `Color.secondary.opacity(0.65)` — .secondary is already ~60% alpha. 217 uses, frequently 11–13pt (task descriptions, due dates, folder names). Likely WCAG AA failures at these sizes. Raise the token; let size/weight de-emphasize.

### [TD-15] 401 error copy is technical and prescribes the harmful action
AI chat failure renders "⚠️ Session expired. Please log out and back in. (HTTP 401)." — jargon, and the advice triggers TD-03. Mail list failure says "Check your connection and try again" when the actual cause was auth. Copy pass: human language, accurate cause, in-place re-auth CTA.

### P3 batch (deduplicated)
- **TD-16** Onboarding truncation: "Incoming messages from your connected ac…", "We only ask once. You can turn each type on or off…" truncated at default type size (sim `j1-05`); remove `lineLimit` or shorten strings.
- **TD-17** "Skip tour" is the big blue primary button while "Show me around" is a ghost link — users pattern-matching "tap the blue one" skip content the step exists to offer. Deliberate inversion, but hierarchy and intent disagree; consider equal-weight buttons.
- **TD-18** Home section links "Open" (32×14pt), "View all" (46×14), "Manage" (47×14) — sub-44pt targets (AX frame sweep on SE). Pad with `contentShape`.
- **TD-19** Archive has no undo anywhere (toast has no action support); Apple Mail sets the expectation. `EmailInboxView.swift:775-782`.
- **TD-20** Color-only state: connection filter chips (enabled = tint only, no `.accessibilityValue`), due-date urgency (overdue = red only) — `EmailInboxView.swift:~1097`, `TaskRowView.swift:460-468`.
- **TD-21** Folder rename can transiently snap back (server-wins `syncSharedFolders`, `TaskCaptureService.swift:546-551`); `addItemToFolder` failure rolls back the count but not the optimistic row (`:891-905`).
- **TD-22** TaskRowView stacks row-Button + nested buttons + `.draggable` + context menu + two swipe sets — VO focus/double-tap ambiguity risk (needs device VO pass).
- **TD-23** Dead `Features/Tasks/CustomTabBar.swift` (never instantiated, a11y-hostile if revived; a second archived copy exists) — delete.
- **TD-24** Settings reachable only via the avatar (top-left); the More tab — where iOS users expect overflow — has no Settings entry.
- **TD-25** Banner stack (`MainTabView.swift:81-101`) overlays the toolbar row rather than reserving space (visual collision in every `j1/j3` screenshot) — same root as TD-01's presentation half.

## 7. Journey walkthroughs

**J1 First-time guest (fresh install → first task):** Startup card (clear) → auth screen (guest link visible) → Reminders step (skipped) → Notifications step (skipped) → tour offer (took tour; 3 cards, fine) → Home. Hesitation points: none until Home, where the false session banner (TD-01) immediately undermines everything. Completion: reached Home in ~60s understanding the app. Confidence: medium — the banner reads as breakage.

**J3 Quick capture:** + FAB → focused composer, keyboard up, mode chips (Auto/Task/Event/Email), contextual default (Task when opened from Tasks). Typed NL date → sent → toast "Task added to Inbox", row grouped under "This week · Tomorrow" with parsed 15:00 due. One accidental scrim tap destroyed a full typed sentence (TD-04); system permission dialog hijacked the success moment (TD-05). Core loop: excellent otherwise.

**J4 Task management:** Row → Edit Task sheet: title/description/progress/priority/due/folder — native controls, explicit Cancel/Save. Views (Board/Table/Dates) present but not deeply exercised this pass.

**J5 Interrupted/returning:** kill + relaunch → task persisted, sensible landing (Home, greeting, This Week shows the task, checklist adapted). Tab state preserved across tab switches; dark-mode switch preserved selected tab.

**J6 Email under failure:** list shows honest skeletons → after ~45–60s "Still checking… This is taking longer than usual. Check your connection and try again." + Try Again. No infinite spinner. Copy misattributes auth failure to connectivity (TD-15).

**J7 AI assistant:** opens with model + Gmail/Calendar status chips, contextual Email chip from the Mail tab, prompt library, first-use **Cloud AI processing consent dialog** (excellent). Send under 401 → message preserved in thread, retry + copy buttons, but the error copy is TD-15.

**J8 Calendar:** tab-level gate explains why access is needed ("If asked, choose Full Access") → system dialog → immediate day view with now-line. Good contextual permission flow.

**J9 More/customization:** Meetings + Docs listed, "Customize Tab Bar — pick up to 4, everything else stays here." Clear.

Not walked (environment): real inbox reading/reply/compose-send, attachments, all-mail search happy path, Meetings, Docs, voice mode, Board/Table/Dates depth, folder drag & drop (needs multi-touch), auto-organize AI review sheet.

## 8. Accessibility audit

- **Core-journey blockers:** TD-02 (Dynamic Type, verified), TD-12 (VO-invisible completion toggle on Inbox rows).
- **VoiceOver:** unlabeled icon buttons (AIChat 9/33, ThreadView 9/18, Home 5/12); CreateSheet not modal, no escape action; toasts never announced; nested-button rows (TD-22). Good: `EmailRowView.swift:92` model combined label ("Unread, Starred, From X…"); native TabView labels; FAB labels present.
- **Dynamic Type:** TD-02. Also 9–11pt chip floors.
- **Motion:** TD-11 (no Reduce Motion gates; pulsing on every pending row).
- **Contrast/color:** TD-14 (`mutedText`), TD-20 (color-only chips/urgency).
- **Touch:** TD-18 sub-44pt Home links; swipe-actions live in `List` rows (VO-exposed — good); drag & drop has full non-gesture parity (context menu "Move to folder", leading swipe, board menus) — genuinely well done.
- **Keyboard/Switch Control:** bare `onTapGesture` rows likely unreachable (TD-12).
- **Verify on hardware:** VO focus order in TaskRowView; CreateSheet modal behavior; real contrast measurements.

## 9. SwiftUI robustness findings

TD-06 (bypassed sync path), TD-07 (query-less refresh clobber), TD-08 (enrichment race), TD-09 (unpersisted mutation queue), TD-10 (dismiss-path save gap + server-wins overwrite), TD-13 (stale model cache window), TD-21 (server-wins rename revert; optimistic-insert rollback mismatch). Verified non-bugs (do not "fix"): `DraftRecord.flushPending` is currently dead code (nothing creates DraftRecords on iOS); offline capture rollback correctly distinguishes network-fail vs server-reject; thread-detail nil path has a proper error + retry state.

## 10. What works and should be preserved

- **Quick-capture loop** — NLP date parse offline, contextual mode preselection, toast+haptic confirmation. This is the product's proof point (sim-verified).
- **Onboarding chain** — honest skip labels, per-step value explanation, adaptive step counter, guest path, context-first permission screens (Reminders/EventKit).
- **Cloud AI processing consent** before the first AI request — rare, real trust-builder.
- **Failure-state discipline** — mail list timeout state with retry; AI chat preserves the failed message with retry/copy.
- **Native TabView + labels, tab-state preservation, customizable bar with fixed More** (`MainTabView.swift:175-200`).
- **Hardened service layer** — `TodosAPIClient` 401-refresh-retry with mutation-safe retry rules; `EmailService` generation-gated loads; persisted delete tombstones; `clientSendId` idempotent send; sign-out PII hygiene (drafts, SwiftData, prefs wiped).
- **Drag & drop with full non-gesture parity**; destructive deletes behind confirmed dialogs with `role: .destructive` (22 files); consistent haptics language; `SwipeBackEnabler` on the two screens that hide the system back button.
- **Dark mode** — intentional, consistent (`#1c1c1e` family).

## 11. Product-level verdict

- **Can users solve their problem?** Task-capture half: yes, verifiably, offline. Email half: architecture looks right but the happy path was untestable here — it is the unproven core.
- **Without assistance?** Yes for capture/navigation; the false session banner is the one thing that would send a user asking "is it broken?"
- **Intuitive?** Yes — native patterns, labeled tabs, plain copy.
- **Faster/safer than alternatives?** Capture beats Reminders' friction. Versus Apple Mail+Reminders, the moat must be the AI connective tissue — unproven without real accounts/users.
- **Would users trust it with real data?** Not yet: TD-01/03/06/10 are exactly the class of issue that kills trust in a data app.
- **Main abandonment reason (predicted):** first-session "Session expired" + any single silent-loss event (rename revert, search vanish, settings revert).
- **Strongest retention reason:** capture + Reminders sync + one-place morning triage.

## 12. Highest-value next actions

Must fix before external testing:
1. TD-01 guest/expired-banner logic + banner layout (small; huge trust win)
2. TD-03 sign-out unsynced-task guard (small; data safety)
3. TD-04 create-sheet draft retention (small; input safety)
4. TD-06 notification-complete sync reroute (one line)

Must fix before App Store:
5. TD-02 Dynamic Type tokens + top-5 screens migration (medium)
6. TD-11 Reduce Motion gates (~7 sites, small)
7. TD-12 VO labeling/traits pass (small-medium)
8. TD-05 permission-prompt gating (small)
9. TD-07 + TD-08 + TD-10 silent-loss trio (each small)

Fast follow: 10. TD-09 persist folder queue; TD-14 token bump; TD-15 error-copy pass; TD-18/19/25.

Requires real-user evidence first: tab-bar six-into-four IA, "Auto" capture routing trust, tour hierarchy (TD-17). Do not build yet: durable Meeting Q&A, iPad layout work (portrait-only iPad needs a decision first — support landscape/iPad properly or ship iPhone-only).

## 13. Unknowns requiring real users

- Is the email experience (real Gmail inbox, reply, send, attachments, search) actually good? Untested here — it's the product's center of gravity.
- Does "Auto" capture routing (AI decides task/event/email) earn trust or feel like a slot machine?
- Is one-calm-workspace enough to displace Mail+Reminders muscle memory (retention)?
- Do users find Meetings/Docs behind More, and do they care?
- Are AI credits (displayed 10×) comprehensible? Willingness to pay?
- Does the notification set (emails, task reminders, AI replies, events) help or churn?
- Tab customization: does anyone use it?

## 14. Evidence appendix

- **Devices/runtimes:** iPhone 17 Pro (iOS 26.4, created for audit), iPhone SE 3rd gen (iOS 26.4, created for audit; visual review of SE screenshots was cut short — layout verified via AX-frame sweep instead). iPhone 17 Pro Max created but unused (deleted).
- **Configurations tested:** light + dark; default + `accessibility-extra-large` content size; fresh install (`--ui-testing-fresh-install` → guest) and returning/seeded (`--ui-testing`, uitest@todus.app, TEST_TOKEN); kill + relaunch.
- **User states:** first-time guest, returning seeded user, error-state user (all API calls 401 against production backend — deliberate failure-path probe), interrupted user (sheet dismissal, process kill).
- **Commands:** `xcodebuildmcp simulator build-and-run` (BUILD SUCCEEDED in 794s; the CLI mis-reported failure due to the known non-fatal `appintentsnltrainingprocessor` SSU stderr line), `simctl` boot/install/launch/screenshot/ui, `xcodebuildmcp ui-automation` tap/type/swipe/snapshot-ui.
- **Screenshots:** 20 captures in session scratchpad (`shots/j1-01…j11-01`): onboarding chain, guest Home with banner, create sheet, capture success + permission dialog, task row/detail, relaunch persistence, mail failure state, AI consent + 401, calendar gate/grant, More, dark mode, AX-XL Tasks.
- **Checks not run:** unit/UI test suites (time-boxed; build verified only), SwiftLint (not configured for iOS target), physical-device VO/contrast measurements, iPad, landscape (unsupported), offline-network toggling (401 probe used instead), real-account email/AI happy paths, Meetings/Docs/voice journeys, folder drag & drop (multi-touch), Board/Table/Dates depth.
- **Environmental blockers:** no real Gmail-connected test account in this environment (OAuth flows can't be exercised headlessly; creating accounts is out of scope for an audit); `TEST_TOKEN` 401s made every network journey a failure-path test by construction.
- **Assumptions:** `--ui-testing` seeded state ≈ post-auth production state minus valid credentials (`AppServices.swift:830-855` confirms flags-only seeding); findings marked "Verified in simulator" were observed on iPhone 17 Pro unless noted.

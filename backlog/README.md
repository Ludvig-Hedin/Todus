# Backlog

Code and agent follow-up work: bugs, nits, deferred fixes, tech debt. **An agent may
pick any open item up and fix it autonomously** when it is confident and the change is
low-risk. Work that a human must do outside the codebase (env vars, dashboards, signing,
accounts) does **not** belong here — it goes in [`../user-tasks/`](../user-tasks/README.md).

## Layout

```
backlog/
  tasks/open/   NNNN-<slug>.md   live, actionable
  tasks/done/   NNNN-<slug>.md   archive — not worked, kept for provenance
```

One file per item, one global 4-digit sequence shared across both folders. Two agents
adding items touch different files instead of fighting over one list.

## Front matter

```yaml
---
id: 0472                       # 4 digits, allocated by the script — never by eye
title: "Short statement of the defect"
status: open                   # open | done
priority: P2                   # P0–P4, optional
tags: [ios, performance]       # optional
files: [apps/ios/.../Foo.swift]  # best-effort paths the fix touches
created: 2026-07-25
source: CODE_REVIEW_BACKLOG.md # where the item came from, when migrated
---
```

Body: the problem **verbatim** (never a summary), `file:line` refs, and a `## Fix shape`
section when the shape is known.

## Working an item

```bash
bun backlog:check                 # prints the next free id + any id collisions
bun backlog:check --json          # same, machine-readable
bun backlog:check --write-readme  # regenerate the table below from the files on disk
```

**Adding one** — allocate the id with `bun backlog:check`, write
`tasks/open/NNNN-<slug>.md`, then regenerate the table.

**Closing one** — `git mv` it to `tasks/done/`, flip `status: done`, and append a
completion note with the date and **evidence**: what you observed (test output, a build,
a reproduced-then-gone symptom), never "should be fixed now".

**Never renumber.** If two files share an id the check script says so; fix the newer
file, leave history alone.

## Migration note (2026-07-25)

These items came from `CODE_REVIEW_BACKLOG.md` and `TASK.md`, split verbatim. Two
routing rules were applied and are worth knowing before you trust a `done`:

- Findings from audits dated **before 2026-06-13** are `done` because that file's own
  resolution pass declared *"No open code defects remain"*. Each such item carries that
  quote in its body. If one is still reproducible, re-open it.
- Sections that named themselves live (`Still open`, `Deferred`, `Needs human review`,
  `Needs attention`, `Pre-existing`) stayed `open` regardless of date, and were split
  one item per finding (bullet or table row).

## Open items

<!-- agent-ops:index:start -->

| id | priority | tags | title |
| --- | --- | --- | --- |
| 0051 | P1 | ios, server, qa, code-review-backlog | [Still open (verified real, deferred — higher-risk / product call / needs backend)](tasks/open/0051-still-open-verified-real-deferred-higher-risk-product-call-n.md) |
| 0052 | P1 | ios, server, qa, code-review-backlog | [IOS-0608-P1 — The whole API client is @MainActor, so the JSON decode + JSONSerialization of the 50-thread mail](tasks/open/0052-ios-0608-p1-the-whole-api-client-is-mainactor-so-the-json-de.md) |
| 0082 | P1 | macos, qa, code-review-backlog | [2026-05-28 — macOS QA deferred features (found, not yet fixed)](tasks/open/0082-2026-05-28-macos-qa-deferred-features-found-not-yet-fixed.md) |
| 0095 | P1 | code-review, code-review-backlog | [apps/server/src/main.ts:1010 — send-email-queue catch deletes statusKV + payloadKV after a send failure withou](tasks/open/0095-apps-server-src-main-ts-1010-send-email-queue-catch-deletes.md) |
| 0461 | P1 | web, todo-sweep, downloads | [Mac DMG download link still points at a placeholder R2 hash](tasks/open/0461-mac-dmg-download-link-still-points-at-a-placeholder-r2-hash.md) |
| 0002 | P2 | code-review, code-review-backlog | [P2 — notification semantics: the iOS notification bell opens a mixed AI digest while its badge count](tasks/open/0002-p2-notification-semantics-the-ios-notification-bell-opens-a.md) |
| 0003 | P2 | code-review, code-review-backlog | [P2 — compound capture retry: if a later intent fails after earlier intents have persisted, retrying](tasks/open/0003-p2-compound-capture-retry-if-a-later-intent-fails-after-earl.md) |
| 0004 | P2 | ios, performance, code-review-backlog | [iOS performance pass — deferred findings, 2026-07-11](tasks/open/0004-ios-performance-pass-deferred-findings-2026-07-11.md) |
| 0015 | P2 | ios, bug-hunt, code-review-backlog | [Bug Hunt — 2026-06-13 — full iOS app (`/bug-hunt`)](tasks/open/0015-bug-hunt-2026-06-13-full-ios-app-bug-hunt.md) |
| 0024 | P2 | macos, code-review, qa, code-review-backlog | [MAC-1 — Test target is defined in project.yml but not runnable yet: xcodebuild test fails resolving MLX's Cmlx](tasks/open/0024-mac-1-test-target-is-defined-in-project-yml-but-not-runnable.md) |
| 0027 | P2 | ios, macos, web, code-review, code-review-backlog | [2026-06-13 — Full-repo review pass (uncommitted iOS/macOS/web + commits 3fc07eae, 2ca46e3b, 22afa335)](tasks/open/0027-2026-06-13-full-repo-review-pass-uncommitted-ios-macos-web-c.md) |
| 0029 | P2 | ios, bug-hunt, code-review, code-review-backlog | [EM-1 — Inbox avatars use raw AsyncImage with no downsampling — 256–512px favicons/apple-touch-icons decoded fu](tasks/open/0029-em-1-inbox-avatars-use-raw-asyncimage-with-no-downsampling-2.md) |
| 0030 | P2 | ios, bug-hunt, code-review, code-review-backlog | [EM-2 — Senders without a bundled icon fire up to 10 sequential favicon GETs per row while scrolling.](tasks/open/0030-em-2-senders-without-a-bundled-icon-fire-up-to-10-sequential.md) |
| 0031 | P2 | ios, bug-hunt, code-review, code-review-backlog | [EM-3 — The well-built disk image cache is bypassed by the inbox (only 2 settings avatars use it); inbox relies](tasks/open/0031-em-3-the-well-built-disk-image-cache-is-bypassed-by-the-inbo.md) |
| 0032 | P2 | ios, bug-hunt, code-review, code-review-backlog | [EM-4 — Known brands (office/azure/monday/beehiiv/disneyplus/postmark/mailerlite/braintree) have slug == nil →](tasks/open/0032-em-4-known-brands-office-azure-monday-beehiiv-disneyplus-pos.md) |
| 0033 | P2 | ios, bug-hunt, code-review, code-review-backlog | [EM-5 — When a 2nd (Gmail) account is linked while one already exists, returns true without verifying the new c](tasks/open/0033-em-5-when-a-2nd-gmail-account-is-linked-while-one-already-ex.md) |
| 0034 | P2 | ios, bug-hunt, code-review, code-review-backlog | [EM-6 — Entire 368-line file (its own SSE/auth pipeline) is dead — never instantiated; compose aiFAB opens AICh](tasks/open/0034-em-6-entire-368-line-file-its-own-sse-auth-pipeline-is-dead.md) |
| 0053 | P2 | ios, server, qa, code-review-backlog | [IOS-0608-P2 — Per-connection filter chips toggle enabledConnectionIds but recomputeFilteredThreads never filte](tasks/open/0053-ios-0608-p2-per-connection-filter-chips-toggle-enabledconnec.md) |
| 0074 | P2 | ios, bug-hunt, code-review-backlog | [BH-0601b-1 — Recipient TextFields tokenize in the Binding set on every keystroke. Typing a separator eats it:](tasks/open/0074-bh-0601b-1-recipient-textfields-tokenize-in-the-binding-set.md) |
| 0078 | P2 | bug-hunt, code-review-backlog | [BH-0601-1 — Before shipping any Slack feature: run pnpm --filter @zero/server db:generate (only schema drift s](tasks/open/0078-bh-0601-1-before-shipping-any-slack-feature-run-pnpm-filter.md) |
| 0083 | P2 | macos, server, qa, code-review-backlog | [Subscription cancel — Cancel hardcodes promonthly, so an annual (proannual) subscriber cancels the wrong produ](tasks/open/0083-subscription-cancel-cancel-hardcodes-promonthly-so-an-annual.md) |
| 0086 | P2 | macos, qa, code-review-backlog | [Reminder scheduling — Request UNUserNotificationCenter auth; schedule a UNCalendarNotificationTrigger on task](tasks/open/0086-reminder-scheduling-request-unusernotificationcenter-auth-sc.md) |
| 0096 | P2 | code-review, code-review-backlog | [apps/server/src/main.ts:772 — .get('.well-known/oauth-authorization-server', ...) is registered without a lead](tasks/open/0096-apps-server-src-main-ts-772-get-well-known-oauth-authorizati.md) |
| 0097 | P2 | code-review, code-review-backlog | [apps/server/src/main.ts:1180 — processExpiredSubscriptions does const { db, conn } = createDb(...), then await](tasks/open/0097-apps-server-src-main-ts-1180-processexpiredsubscriptions-doe.md) |
| 0408 | P2 | task-md, sprint | [N6-02 moved to BLOCKED: current ElevenLabs implementation in web depends on browser-only APIs (apps/](tasks/open/0408-n6-02-moved-to-blocked-current-elevenlabs-implementation-in.md) |
| 0418 | P2 | task-md, sprint | [N8-01 moved to BLOCKED after implementing screenshot governance artifacts in /parityscreenshots (man](tasks/open/0418-n8-01-moved-to-blocked-after-implementing-screenshot-governa.md) |
| 0464 | P2 | server, todo-sweep, ai | [Mail assistant hardcodes UTC instead of the user timezone](tasks/open/0464-mail-assistant-hardcodes-utc-instead-of-the-user-timezone.md) |
| 0466 | P2 | macos, todo-sweep, ux | [macOS content header buttons are wired to nothing](tasks/open/0466-macos-content-header-buttons-are-wired-to-nothing.md) |
| 0468 | P2 | macos, todo-sweep, local-ai | [HuggingFace cache bridge replaces the symlink non-atomically](tasks/open/0468-huggingface-cache-bridge-replaces-the-symlink-non-atomically.md) |
| 0469 | P2 | macos, todo-sweep, sharing | [todus://share deep link has no presenter on macOS](tasks/open/0469-todus-share-deep-link-has-no-presenter-on-macos.md) |
| 0474 | P2 | web, tooling, dx | [apps/web cannot be typechecked whole-program — tsc OOMs at 11 GB heap](tasks/open/0474-apps-web-whole-program-typecheck-oom.md) |
| 0005 | P3 | ios, performance, code-review-backlog | [PERF-6 — tasksChangeDigest/boardChangeDigest walk allTasks O(n) on every body eval (they're the .onChange comp](tasks/open/0005-perf-6-taskschangedigest-boardchangedigest-walk-alltasks-o-n.md) |
| 0006 | P3 | ios, performance, code-review-backlog | [PERF-7 — Per-SSE-line Task.detached decode (hundreds of hops/reply) and full-markdown reparse on every 80ms to](tasks/open/0006-perf-7-per-sse-line-task-detached-decode-hundreds-of-hops-re.md) |
| 0007 | P3 | ios, bug-hunt, ux, code-review-backlog | [iOS UX assessment + polish + bug hunt — 2026-07-07 (apps/ios)](tasks/open/0007-ios-ux-assessment-polish-bug-hunt-2026-07-07-apps-ios.md) |
| 0008 | P3 | ios, bug-hunt, ux, code-review-backlog | [Deferred (product decisions)](tasks/open/0008-deferred-product-decisions.md) |
| 0010 | P3 | code-review, code-review-backlog | [Pre-push full-repo review — 2026-06-20](tasks/open/0010-pre-push-full-repo-review-2026-06-20.md) |
| 0011 | P3 | code-review, code-review-backlog | [Pre-existing (not introduced by these commits — out of scope, left as-is)](tasks/open/0011-pre-existing-not-introduced-by-these-commits-out-of-scope-le.md) |
| 0012 | P3 | code-review, code-review-backlog | [Server tsc --noEmit reports type errors in routes/agent/mcp.ts, thread-workflow-utils/workflow-funct](tasks/open/0012-server-tsc-noemit-reports-type-errors-in-routes-agent-mcp-ts.md) |
| 0013 | P3 | ios, ux, code-review-backlog | [iOS UX hardening pass — 2026-06-15 (whole-app, main user-flow surfaces)](tasks/open/0013-ios-ux-hardening-pass-2026-06-15-whole-app-main-user-flow-su.md) |
| 0014 | P3 | ios, bug-hunt, code-review-backlog | [Bug Hunt — 2026-06-14 (iOS main user-flow surfaces)](tasks/open/0014-bug-hunt-2026-06-14-ios-main-user-flow-surfaces.md) |
| 0016 | P3 | web, code-review-backlog | [Web → Native parity — deferred sub-items (2026-06-13)](tasks/open/0016-web-native-parity-deferred-sub-items-2026-06-13.md) |
| 0017 | P3 | web, code-review-backlog | [PAR-A2 — ✅ MOSTLY DONE — visibility toggles shipped via eventsMulti (no server change). REMAINING: (1) create](tasks/open/0017-par-a2-mostly-done-visibility-toggles-shipped-via-eventsmult.md) |
| 0018 | P3 | web, code-review-backlog | [PAR-B3 — Audit flagged that @-mention context may not actually be injected into the agent system prompt (UI-on](tasks/open/0018-par-b3-audit-flagged-that-mention-context-may-not-actually-b.md) |
| 0019 | P3 | web, code-review-backlog | [PAR-B-TEST — New task/calendar tools are DB/Google-backed; no automated test (server suite has no DB harness).](tasks/open/0019-par-b-test-new-task-calendar-tools-are-db-google-backed-no-a.md) |
| 0021 | P3 | web, code-review-backlog | [PAR-SIG (not a gap) — Audit flagged per-account signatures as a web localStorage \"data-loss bug\". On re-check](tasks/open/0021-par-sig-not-a-gap-audit-flagged-per-account-signatures-as-a.md) |
| 0022 | P3 | macos, qa, code-review-backlog | [macOS QA pass — 2026-06-13 — email loading / thread-open / hangs](tasks/open/0022-macos-qa-pass-2026-06-13-email-loading-thread-open-hangs.md) |
| 0023 | P3 | macos, code-review, qa, code-review-backlog | [Needs human review (deferred)](tasks/open/0023-needs-human-review-deferred.md) |
| 0025 | P3 | macos, code-review, qa, code-review-backlog | [MAC-2 — Message list is an eager VStack (not LazyVStack); WebViews are gated by isExpanded so open cost is bou](tasks/open/0025-mac-2-message-list-is-an-eager-vstack-not-lazyvstack-webview.md) |
| 0026 | P3 | macos, code-review, qa, code-review-backlog | [MAC-3 — A→B→A interleaved folder switches can let a slow superseded load commit to the cache (the live-threads](tasks/open/0026-mac-3-a-b-a-interleaved-folder-switches-can-let-a-slow-super.md) |
| 0028 | P3 | ios, bug-hunt, code-review, code-review-backlog | [Needs human review (verified real, deferred — higher-risk / unvalidatable under `--ui-testing` / product calls)](tasks/open/0028-needs-human-review-verified-real-deferred-higher-risk-unvali.md) |
| 0035 | P3 | ios, bug-hunt, code-review, code-review-backlog | [EM-7 — Full-list lowercasing per keystroke; threadsForSender re-filters+sorts the pool in a computed prop ever](tasks/open/0035-em-7-full-list-lowercasing-per-keystroke-threadsforsender-re.md) |
| 0036 | P3 | ios, bug-hunt, code-review, code-review-backlog | [EM-8 — Copies plainText (snippet) not the full message — same root as the Forward bug.](tasks/open/0036-em-8-copies-plaintext-snippet-not-the-full-message-same-root.md) |
| 0037 | P3 | ios, bug-hunt, code-review, code-review-backlog | [EM-9 — Archiving/deleting the currently-open thread doesn't clear selectedThreadId; detail can dangle on a rem](tasks/open/0037-em-9-archiving-deleting-the-currently-open-thread-doesn-t-cl.md) |
| 0038 | P3 | ios, bug-hunt, code-review, code-review-backlog | [EM-10 — A stale fromConnectionId (connection removed) silently flatMaps to nil → sends from the default mailbo](tasks/open/0038-em-10-a-stale-fromconnectionid-connection-removed-silently-f.md) |
| 0042 | P3 | macos, qa, code-review-backlog | [QA-0608-1 — One errorMessage field is shared by load + markRead/unread + archive/delete/star + connectGmail an](tasks/open/0042-qa-0608-1-one-errormessage-field-is-shared-by-load-markread.md) |
| 0043 | P3 | macos, qa, code-review-backlog | [QA-0608-2 — Compose sheet binds to detail?.messages.last; opening reply/forward before the thread finishes loa](tasks/open/0043-qa-0608-2-compose-sheet-binds-to-detail-messages-last-openin.md) |
| 0044 | P3 | macos, qa, code-review-backlog | [QA-0608-3 — Switching the From account appends the new signature without stripping the old (comment claims it](tasks/open/0044-qa-0608-3-switching-the-from-account-appends-the-new-signatu.md) |
| 0045 | P3 | macos, qa, code-review-backlog | [QA-0608-4 — A transient per-item mail.get failure during refresh drops that thread from the enriched set, and](tasks/open/0045-qa-0608-4-a-transient-per-item-mail-get-failure-during-refre.md) |
| 0046 | P3 | macos, qa, code-review-backlog | [QA-0608-5 — The flag is read by canSave/calendarPicker but never set to true anywhere → the \"original calendar](tasks/open/0046-qa-0608-5-the-flag-is-read-by-cansave-calendarpicker-but-nev.md) |
| 0048 | P3 | macos, qa, code-review-backlog | [QA-0608-7 — No auto-advance: a user who signed in with Google already has a Gmail connection but is still show](tasks/open/0048-qa-0608-7-no-auto-advance-a-user-who-signed-in-with-google-a.md) |
| 0054 | P3 | ios, server, qa, code-review-backlog | [IOS-0608-2 — Long-press create-event no-ops with no feedback when no writable calendar (rarer than first repor](tasks/open/0054-ios-0608-2-long-press-create-event-no-ops-with-no-feedback-w.md) |
| 0055 | P3 | ios, server, qa, code-review-backlog | [IOS-0608-P3 — Messages render in a non-lazy VStack ForEach inside a ScrollView; every expanded MessageRow owns](tasks/open/0055-ios-0608-p3-messages-render-in-a-non-lazy-vstack-foreach-ins.md) |
| 0061 | P3 | ios, macos, bug-hunt, code-review-backlog | [Needs attention (not auto-fixed — TODO added in code where noted)](tasks/open/0061-needs-attention-not-auto-fixed-todo-added-in-code-where-note.md) |
| 0062 | P3 | ios, macos, bug-hunt, code-review-backlog | [BH-0605-1 — Coalesced load can surface a foreign CancellationError if evict/unloadAll cancels the task during](tasks/open/0062-bh-0605-1-coalesced-load-can-surface-a-foreign-cancellatione.md) |
| 0063 | P3 | ios, macos, bug-hunt, code-review-backlog | [BH-0605-2 — Non-atomic symlink remove+recreate; nonisolated static with no serialization → concurrent refresh(](tasks/open/0063-bh-0605-2-non-atomic-symlink-remove-recreate-nonisolated-sta.md) |
| 0067 | P3 | ios, macos, bug-hunt, code-review-backlog | [BH-0605-6 — When a connection's calendar list isn't loaded yet, GoogleCalendarService.events falls back to fet](tasks/open/0067-bh-0605-6-when-a-connection-s-calendar-list-isn-t-loaded-yet.md) |
| 0073 | P3 | ios, bug-hunt, code-review-backlog | [Needs attention (not auto-fixed)](tasks/open/0073-needs-attention-not-auto-fixed.md) |
| 0077 | P3 | bug-hunt, code-review-backlog | [Needs attention (not auto-fixed)](tasks/open/0077-needs-attention-not-auto-fixed-2.md) |
| 0079 | P3 | bug-hunt, code-review-backlog | [BH-0601-2 — fetchThreadDetail dedup: a foreground tap (updateLoadingState:true) that joins an in-flight prefet](tasks/open/0079-bh-0601-2-fetchthreaddetail-dedup-a-foreground-tap-updateloa.md) |
| 0080 | P3 | bug-hunt, code-review-backlog | [BH-0601-3 — legacyCalendarEvent.id switched from composite (apple:/google:) to raw providerEventId. SwiftUI li](tasks/open/0080-bh-0601-3-legacycalendarevent-id-switched-from-composite-app.md) |
| 0084 | P3 | macos, server, qa, code-review-backlog | [iOS markdown email send — macOS now converts the compose markdown body → HTML before send (commit ed8eb057), b](tasks/open/0084-ios-markdown-email-send-macos-now-converts-the-compose-markd.md) |
| 0085 | P3 | macos, server, qa, code-review-backlog | [Email attachment download — Add a backend attachment-fetch endpoint (mail.getAttachment), then wire tap → down](tasks/open/0085-email-attachment-download-add-a-backend-attachment-fetch-end.md) |
| 0087 | P3 | macos, qa, code-review-backlog | [Move to folder — Add a \"Move to…\" context-menu submenu listing folders; add EmailService.move(ids:toFolder:) c](tasks/open/0087-move-to-folder-add-a-move-to-context-menu-submenu-listing-fo.md) |
| 0088 | P3 | macos, qa, code-review-backlog | [Compose-card CC/BCC input — CC/BCC rows render existing recipients but provide no field to add any — addRecipi](tasks/open/0088-compose-card-cc-bcc-input-cc-bcc-rows-render-existing-recipi.md) |
| 0089 | P3 | macos, qa, code-review-backlog | [Deferred — medium / low (client, but untestable here)](tasks/open/0089-deferred-medium-low-client-but-untestable-here.md) |
| 0090 | P3 | macos, qa, code-review-backlog | [Notification cold-launch — Queue the routing intent (category + payload) on the app delegate when services/mod](tasks/open/0090-notification-cold-launch-queue-the-routing-intent-category-p.md) |
| 0091 | P3 | macos, qa, code-review-backlog | [Event-edit prefill — In edit mode location/notes are hardcoded to \"\" because CalendarEvent doesn't carry them;](tasks/open/0091-event-edit-prefill-in-edit-mode-location-notes-are-hardcoded.md) |
| 0094 | P3 | code-review, code-review-backlog | [Needs human review (5)](tasks/open/0094-needs-human-review-5.md) |
| 0098 | P3 | code-review, code-review-backlog | [apps/server/src/main.ts:1240 — \\[SCHEDULED] Processed ${allAccounts.keys.length} accounts\\ — allAccounts.keys](tasks/open/0098-apps-server-src-main-ts-1240-scheduled-processed-allaccounts.md) |
| 0099 | P3 | code-review, code-review-backlog | [apps/server/src/main.ts:1295 — .post('/a8n/notify/:providerId') returns a response only when providerId === EP](tasks/open/0099-apps-server-src-main-ts-1295-post-a8n-notify-providerid-retu.md) |
| 0100 | P3 | web, bug-hunt, code-review, code-review-backlog | [apps/web/hooks/use-optimistic-actions.ts:347 — typeActions?.size === 1 is checked AFTER typeActions.delete(pen](tasks/open/0100-apps-web-hooks-use-optimistic-actions-ts-347-typeactions-siz.md) |
| 0101 | P3 | macos, bug-hunt, code-review, code-review-backlog | [apps/macos/TodusMac/Services/Tasks/LocalTaskParsingService.swift:75 — daysAhead <= 0 { daysAhead += 7 } — typi](tasks/open/0101-apps-macos-todusmac-services-tasks-localtaskparsingservice-s.md) |
| 0102 | P3 | macos, bug-hunt, code-review, code-review-backlog | [apps/macos/TodusMac/Views/Email/MacEmailThreadView.swift:245-262 — Compose sheet renders empty content if deta](tasks/open/0102-apps-macos-todusmac-views-email-macemailthreadview-swift-245.md) |
| 0103 | P3 | macos, bug-hunt, code-review, code-review-backlog | [apps/macos/TodusMac/Services/Voice/GeminiLiveProvider.swift:271-279 — Captures let task = self.webSocketTask a](tasks/open/0103-apps-macos-todusmac-services-voice-geminiliveprovider-swift.md) |
| 0104 | P3 | macos, bug-hunt, code-review-backlog | [Open Items](tasks/open/0104-open-items.md) |
| 0106 | P3 | ios, bug-hunt, code-review-backlog | [Unverified leads (investigator candidates that need a closer look)](tasks/open/0106-unverified-leads-investigator-candidates-that-need-a-closer.md) |
| 0107 | P3 | ios, bug-hunt, code-review-backlog | [apps/ios/Todus/Todus/Services/AI/AIChatService.swift — claims of (a) partial JSON in tool arguments](tasks/open/0107-apps-ios-todus-todus-services-ai-aichatservice-swift-claims.md) |
| 0108 | P3 | ios, bug-hunt, code-review-backlog | [apps/ios/Todus/Todus/Services/Tasks/SupabaseSyncService.swift:45 — claim that queue.popLast() races](tasks/open/0108-apps-ios-todus-todus-services-tasks-supabasesyncservice-swif.md) |
| 0109 | P3 | ios, bug-hunt, code-review-backlog | [apps/ios/Todus/Todus/Services/Reminders/AppleRemindersSyncService.swift:359 — off-by-one in maxCoale](tasks/open/0109-apps-ios-todus-todus-services-reminders-applereminderssyncse.md) |
| 0110 | P3 | ios, bug-hunt, code-review-backlog | [apps/ios/Todus/Todus/Features/Calendar/CalendarTimeGridView.swift:295 — multi-day event height colla](tasks/open/0110-apps-ios-todus-todus-features-calendar-calendartimegridview.md) |
| 0111 | P3 | ios, bug-hunt, code-review-backlog | [apps/ios/Todus/Todus/Features/Calendar/CalendarMultiDayView.swift:346 — claim that startOfDay(for: e](tasks/open/0111-apps-ios-todus-todus-features-calendar-calendarmultidayview.md) |
| 0112 | P3 | ios, bug-hunt, code-review-backlog | [apps/ios/Todus/Todus/Services/Calendar/GoogleCalendarService.swift:316–333 — fetchCalendars(for:) ca](tasks/open/0112-apps-ios-todus-todus-services-calendar-googlecalendarservice.md) |
| 0201 | P3 | task-md, sprint | [Device smoke test (attachment round-trip, idempotent send) — REMAINING](tasks/open/0201-device-smoke-test-attachment-round-trip-idempotent-send-rema.md) |
| 0263 | P3 | task-md, sprint | [PENDING Apple mail-client capability enablement (iOS + macOS, 2026-04): Todus already registers mail](tasks/open/0263-pending-apple-mail-client-capability-enablement-ios-macos-20.md) |
| 0347 | P3 | task-md, sprint | [INPROGRESS Apply targeted fixes for AI profile prompt safety, session freshness filtering, and devic](tasks/open/0347-inprogress-apply-targeted-fixes-for-ai-profile-prompt-safety.md) |
| 0352 | P3 | task-md, sprint | [PENDING Verify whether the web settings-general AI profile fields exist in this branch before adding](tasks/open/0352-pending-verify-whether-the-web-settings-general-ai-profile-f.md) |
| 0358 | P3 | task-md, sprint | [PENDING Cross-device near-live sync architecture across tasks, folders, settings, and AI state.](tasks/open/0358-pending-cross-device-near-live-sync-architecture-across-task.md) |
| 0462 | P3 | server, todo-sweep, outlook | [Outlook subscription factory is three unimplemented stubs](tasks/open/0462-outlook-subscription-factory-is-three-unimplemented-stubs.md) |
| 0463 | P3 | server, todo-sweep, performance | [mail.ts label modification has no batching](tasks/open/0463-mail-ts-label-modification-has-no-batching.md) |
| 0465 | P3 | server, web, macos, todo-sweep, realtime | [Group chat is polling-based; realtime needs a Durable Object room](tasks/open/0465-group-chat-is-polling-based-realtime-needs-a-durable-object.md) |
| 0009 | P4 | ios, bug-hunt, ux, code-review-backlog | [docs/ios-followup-tasks.md (2026-07-08): tasks 1–4 + 7 (dynamic tab bar BH-0613-6, in-composer attac](tasks/open/0009-docs-ios-followup-tasks-md-2026-07-08-tasks-1-4-7-dynamic-ta.md) |
| 0020 | P4 | web, code-review-backlog | [PAR-F1 — to=\"/forgot-password\" is a dead link — no such route. Low priority (auth is OTP/Google-primary; email](tasks/open/0020-par-f1-to-forgot-password-is-a-dead-link-no-such-route-low-p.md) |
| 0039 | P4 | ios, bug-hunt, code-review, code-review-backlog | [EM-11 — Pagination appends new ids without re-sort (documented contract) — a page-2 thread newer than page-1's](tasks/open/0039-em-11-pagination-appends-new-ids-without-re-sort-documented.md) |
| 0040 | P4 | ios, bug-hunt, code-review, code-review-backlog | [EM-12 — 0.7s asyncAfter not cancelled on teardown (weak-guarded so safe, just wasteful).](tasks/open/0040-em-12-0-7s-asyncafter-not-cancelled-on-teardown-weak-guarded.md) |
| 0041 | P4 | macos, qa, code-review-backlog | [Needs attention (not auto-fixed — verified real, deferred as higher-risk/product calls)](tasks/open/0041-needs-attention-not-auto-fixed-verified-real-deferred-as-hig.md) |
| 0047 | P4 | macos, qa, code-review-backlog | [QA-0608-6 — Comments say the calendar picker is \"disabled in edit mode\" but it has no .disabled(); changing it](tasks/open/0047-qa-0608-6-comments-say-the-calendar-picker-is-disabled-in-ed.md) |
| 0049 | P4 | macos, qa, code-review-backlog | [QA-0608-8 — Step is fully implemented (sets hasConfiguredDefaultMailPrompt) but never presented — no gate bran](tasks/open/0049-qa-0608-8-step-is-fully-implemented-sets-hasconfigureddefaul.md) |
| 0050 | P4 | macos, qa, code-review-backlog | [QA-0608-9 — A thread opened from search (not in threads) marks-read fire-and-forget; optimistic update + rollb](tasks/open/0050-qa-0608-9-a-thread-opened-from-search-not-in-threads-marks-r.md) |
| 0056 | P4 | ios, server, qa, code-review-backlog | [IOS-0608-P4 — Open-thread star is local @State from mail.get; starring from the inbox swipe (now optimistic on](tasks/open/0056-ios-0608-p4-open-thread-star-is-local-state-from-mail-get-st.md) |
| 0057 | P4 | ios, server, qa, code-review-backlog | [IOS-0608-7 — Bold/list/H1 append at end of body, ignoring caret.](tasks/open/0057-ios-0608-7-bold-list-h1-append-at-end-of-body-ignoring-caret.md) |
| 0058 | P4 | ios, server, qa, code-review-backlog | [IOS-0608-9 — Tab \"Email\" vs page header \"Mail\" — cross-platform naming call (left unchanged to avoid iOS-only](tasks/open/0058-ios-0608-9-tab-email-vs-page-header-mail-cross-platform-nami.md) |
| 0059 | P4 | ios, server, qa, code-review-backlog | [IOS-0608-10 — Dead file, zero call sites — needs .pbxproj removal (skipped to avoid project-file surgery).](tasks/open/0059-ios-0608-10-dead-file-zero-call-sites-needs-pbxproj-removal.md) |
| 0060 | P4 | ios, server, qa, code-review-backlog | [IOS-0608-P5 — Optimistically removes the open-loop row but never re-adds on server failure (dismiss/complete s](tasks/open/0060-ios-0608-p5-optimistically-removes-the-open-loop-row-but-nev.md) |
| 0064 | P4 | ios, macos, bug-hunt, code-review-backlog | [BH-0605-3 — External-cache size measured over repo root (blobs/ + snapshots/) while the weight check scans onl](tasks/open/0064-bh-0605-3-external-cache-size-measured-over-repo-root-blobs.md) |
| 0065 | P4 | ios, macos, bug-hunt, code-review-backlog | [BH-0605-4 — initialScan merge can resurrect a just-deleted model as .installed if scanDisk() snapshotted befor](tasks/open/0065-bh-0605-4-initialscan-merge-can-resurrect-a-just-deleted-mod.md) |
| 0066 | P4 | ios, macos, bug-hunt, code-review-backlog | [BH-0605-5 — Dragging an event to a new time then a failed store.save leaves the pill visually moved (no reload](tasks/open/0066-bh-0605-5-dragging-an-event-to-a-new-time-then-a-failed-stor.md) |
| 0068 | P4 | ios, macos, bug-hunt, code-review-backlog | [BH-0605-7 — On failed audio capture, a trailing provider event between consumer-cancel and provider.disconnect](tasks/open/0068-bh-0605-7-on-failed-audio-capture-a-trailing-provider-event.md) |
| 0069 | P4 | ios, macos, bug-hunt, code-review-backlog | [BH-0605-8 — onDisappear flush + an already-in-flight debounced saveTitleNow can issue two concurrent renameDoc](tasks/open/0069-bh-0605-8-ondisappear-flush-an-already-in-flight-debounced-s.md) |
| 0070 | P4 | ios, macos, bug-hunt, code-review-backlog | [BH-0605-9 — center.add(request) fire-and-forget swallows scheduling errors (e.g. the 64-pending OS cap) → a re](tasks/open/0070-bh-0605-9-center-add-request-fire-and-forget-swallows-schedu.md) |
| 0071 | P4 | ios, macos, bug-hunt, code-review-backlog | [BH-0605-10 — \"Used X of Y credits\" can show used > limit when over quota (only aiUsagePercent is clamped) — co](tasks/open/0071-bh-0605-10-used-x-of-y-credits-can-show-used-limit-when-over.md) |
| 0072 | P4 | ios, macos, bug-hunt, code-review-backlog | [BH-0605-11 — Dragging a tab above Home triggers an in-onMove re-pin that snaps it back below Home (confusing);](tasks/open/0072-bh-0605-11-dragging-a-tab-above-home-triggers-an-in-onmove-r.md) |
| 0075 | P4 | ios, bug-hunt, code-review-backlog | [BH-0601b-2 — Person results render a custom 34pt gray-initials ZStack, while the inbox People tab uses 40pt Se](tasks/open/0075-bh-0601b-2-person-results-render-a-custom-34pt-gray-initials.md) |
| 0076 | P4 | ios, bug-hunt, code-review-backlog | [BH-0601b-3 — Same sender renders at 40pt in the inbox list but 36pt in thread detail (MessageRow). Avatar visi](tasks/open/0076-bh-0601b-3-same-sender-renders-at-40pt-in-the-inbox-list-but.md) |
| 0081 | P4 | bug-hunt, code-review-backlog | [BH-0601-4 — hasWeightFile/directorySize recursively walk multi-GB HF caches with no depth/count cap and no mid](tasks/open/0081-bh-0601-4-hasweightfile-directorysize-recursively-walk-multi.md) |
| 0092 | P4 | macos, qa, code-review-backlog | [In-chat model menu — The menu lists only the cloud models with a checkmark; a local model selected from Settin](tasks/open/0092-in-chat-model-menu-the-menu-lists-only-the-cloud-models-with.md) |
| 0093 | P4 | macos, qa, code-review-backlog | [Dead .paused UI — The .paused state (caption + \"Resume\") is rendered but never produced — ModelDownloadService](tasks/open/0093-dead-paused-ui-the-paused-state-caption-resume-is-rendered-b.md) |
| 0105 | P4 | macos, bug-hunt, code-review-backlog | [001 — home/page.tsx defines its own inline TaskItem component instead of importing the shared components/tasks](tasks/open/0105-001-home-page-tsx-defines-its-own-inline-taskitem-component.md) |
| 0467 | P4 | macos, todo-sweep, dead-code | [MacHomeView keeps dead assistant strip / queue column code](tasks/open/0467-machomeview-keeps-dead-assistant-strip-queue-column-code.md) |
| 0470 | P4 | ios, todo-sweep, ai | [iOS AI chat thumbs up/down goes nowhere](tasks/open/0470-ios-ai-chat-thumbs-up-down-goes-nowhere.md) |
| 0471 | P4 | web, todo-sweep, i18n | [Navigation labels fall back to hardcoded English](tasks/open/0471-navigation-labels-fall-back-to-hardcoded-english.md) |

<!-- agent-ops:index:end -->

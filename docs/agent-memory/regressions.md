# Regressions

Every fixed bug worth not reintroducing: symptom, cause, fix, test, keywords.

**Grep this file before you review, refactor, or "fix" something.** A finding that looks
new is often one of these, already understood and already paid for.

Format:

```
## <short symptom>
- **Symptom:** what a user or agent observes
- **Cause:** the actual mechanism
- **Fix:** what was changed
- **Test:** what proves it stays fixed (or "none — manual only")
- **Keywords:** grep bait
- **Source:** changelog entry / commit
```

---

## macOS app SIGTRAPs on every launch

- **Symptom:** the macOS app crashes at startup with `EXC_BREAKPOINT`.
- **Cause:** `TaskSyncService.retryUnsyncedTasks` ran a compound `||` string-equality
  `#Predicate` fetch. SwiftData traps on that predicate shape, and the call runs at
  launch/foreground via `flushPendingSync`.
- **Fix:** fetch-all plus an in-memory filter.
- **Test:** none — reproduced by launching the app.
- **Keywords:** SwiftData, #Predicate, EXC_BREAKPOINT, compound predicate, launch crash
- **Source:** `changelog/entries/` — macOS Flow QA round 3.

## Calendar grid edit/delete always 404s

- **Symptom:** editing or deleting an event from the calendar grid fails every time.
- **Cause:** the composite namespaced id (`apple:` / `google:` prefix) was passed to
  `EKEventStore.event(withIdentifier:)`, which never matches a prefixed id.
- **Fix:** use the raw `providerEventId`.
- **Test:** none — verified in app.
- **Keywords:** EKEventStore, event(withIdentifier:), composite id, calendar 404
- **Source:** `changelog/entries/` — macOS Flow QA round 2.

## Sent mail can duplicate on retry

- **Symptom:** a retried send delivers the message twice.
- **Cause:** no idempotency key on `mail.send`.
- **Fix:** `mail.send` accepts `clientSendId`, deduped in KV on both the immediate and
  scheduled paths; iOS sends the draft's stable id.
- **Test:** server-side dedupe tests.
- **Caveat:** the key is only honoured by a **deployed** server — zod strips unknown keys
  on an old deploy, so ship the server before the native build (`user-tasks/` 0002).
- **Keywords:** clientSendId, idempotency, double send, mail.send
- **Source:** `changelog/entries/` — iOS triple audit follow-up.

## Cross-device task deletions resurrect

- **Symptom:** a task deleted on one device comes back on another.
- **Cause:** deletion was inferred from absence in offset pagination, and stale offline
  upserts could re-create rows.
- **Fix:** the server journals explicit deletions in `task_deletion`; `tasks.deleted`
  pages that evidence to clients; deletion wins over stale offline upserts; reminder and
  notification mirrors are cleaned only **after** the local delete commits.
- **Test:** focused task-sync tests.
- **Keywords:** task_deletion, tombstone, tasks.deleted, offline upsert, resurrect
- **Source:** `changelog/entries/` — iOS performance and reliability follow-up.

## xcodegen silently drops the MLX packages (macOS)

- **Symptom:** after `xcodegen generate`, the macOS target fails to resolve `Cmlx` /
  `_NumericsShims`; MLX references drop from 19 to 4.
- **Cause:** `project.yml` had no `packages:` section, so SPM packages added through the
  Xcode UI were not represented and every regeneration removed them.
- **Fix:** declare `mlx-swift-examples` in `project.yml` and link `MLXLLM` / `MLXLMCommon`
  on the app target.
- **Test:** `xcodebuild test -scheme TodusMacTests` (11/11).
- **Keywords:** xcodegen, project.yml, packages:, MLX, Cmlx, regen-safe
- **Source:** `changelog/entries/` — backlog resolution pass, sixth batch.

## AI chat history leaks between accounts on a shared Mac

- **Symptom:** conversations from a previous user appear after signing in as someone else.
- **Cause:** conversations persisted under a static, non-user-scoped Keychain key and were
  never cleared on sign-out.
- **Fix:** `MacAIChatService.resetForSignOut()` clears in-memory state and overwrites the
  caches; called from `MacAppServices.signOut()`.
- **Test:** none — verified manually.
- **Keywords:** Keychain, sign out, account leak, MacAIChatService, privacy
- **Source:** `changelog/entries/` — macOS Flow QA.

## iOS List / Form paint pure black in dark mode

- **Symptom:** dark surfaces render `#000000` instead of the canonical `#1c1c1e`.
- **Cause:** `List` / `Form` (and CalendarKit) paint their own `systemBackground`, which
  covers the app background.
- **Fix:** `.scrollContentBackground(.hidden)` plus `AppTheme.backgroundTop` /
  `sheetBackground`; for CalendarKit set `style.timeline` / `.header.backgroundColor`.
  macOS is unaffected.
- **Test:** screenshot parity run.
- **Keywords:** scrollContentBackground, systemBackground, 1c1c1e, dark mode, CalendarKit
- **Source:** `DESIGN_SYSTEM.md`, iOS design-system pass.

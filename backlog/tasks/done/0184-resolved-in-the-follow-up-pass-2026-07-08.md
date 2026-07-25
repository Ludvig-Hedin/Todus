---
id: 0184
title: "Resolved in the follow-up pass (2026-07-08)"
status: done
tags: [ios, bug-hunt, ux, code-review-backlog]
files: []
created: 2026-07-07
source: CODE_REVIEW_BACKLOG.md
---

> Source context: iOS UX assessment + polish + bug hunt — 2026-07-07 (apps/ios)

## Resolved in the follow-up pass (2026-07-08)

- ~~Account deletion~~ — flow is now verification-aware: the app no longer wipes local data / signs out on the delete request; it tells the user to check their email (deletion completes via the emailed link; the eventual 401 signs the device out). `Origin` header added.
- ~~Received email attachments can't be opened~~ — the server already exposes `mail.getMessageAttachments` (base64 content); attachment cards now download on tap (per-card spinner) and open in the shared preview sheet, with error copy on failure.
- ~~Composed email attachments never uploaded~~ — the server's `mail.send` already accepts `serializedFileSchema`; iOS now uploads chips inline (base64) with the send. Compose body is also converted from the toolbar's light Markdown to HTML so recipients don't see literal `**bold**` markers (resolves the backend-rendering question — the server forwards `message` as-is).
- ~~Global search email local-only~~ — global search now runs a debounced server-side search via a new non-clobbering `EmailService.searchThreadsServer`, merged (deduped) with the instant local matches.
- ~~Offline task deletions lost on kill~~ — pending delete retries now persist to UserDefaults (SyncMutation is Codable) and restore on launch; no schema change needed.
- ~~Draft double-send~~ — `mail.send` now accepts a `clientSendId` idempotency key (KV-deduped server-side, both immediate and scheduled paths); iOS sends the draft's stable id, and `flushPending` safely retries drafts stuck in "sending" again. ⚠️ Deploy the server before shipping the iOS build — until the server is deployed the key is ignored (zod strips unknown keys) and retries behave like before.
- ~~HomeView dead code~~ — `summaryLine`, `topPriority`, `topPriorityRow`, `HomeTopPriority` deleted (~150 lines).

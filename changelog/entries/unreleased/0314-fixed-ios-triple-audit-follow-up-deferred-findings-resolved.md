---
id: 0314
title: "Fixed — iOS triple audit follow-up: deferred findings resolved"
status: unreleased
category: Fixed
release_date: 2026-07-08
source: CHANGELOG.md
---

### Fixed — iOS triple audit follow-up: deferred findings resolved, 2026-07-08

Second wave closing out the items the 2026-07-07 audit deferred:

- **Email attachments now actually work end-to-end on iOS** — received attachments download on tap (via the existing `mail.getMessageAttachments` endpoint) and open in the shared preview sheet; composed attachments upload inline with `mail.send` (the server already accepted `serializedFileSchema` — the client just never sent them). The "can't be sent yet" caption is gone.
- **Compose bodies are converted to HTML on send** — the iOS formatting toolbar's light Markdown (`**bold**`, `# headers`, bullets) previously reached recipients as literal markers because the server forwards `message` as-is. New `EmailService.composeBodyToHTML` escapes + converts (passes through bodies that are already HTML).
- **Account deletion is verification-aware** — the app no longer wipes local data and signs out when the backend has only sent a confirmation email (passwordless accounts). It now explains that deletion completes via the emailed link and keeps everything intact until then.
- **Global search covers all mail** — a debounced server-side search (new non-clobbering `EmailService.searchThreadsServer`) merges with the instant local results, so body-text matches and unloaded threads appear.
- **`mail.send` gained a `clientSendId` idempotency key** (server: KV-deduped on both the immediate and scheduled paths) and iOS drafts send their stable record id — crash-retry of in-flight sends is now safe, so `flushPending` again auto-retries drafts stuck in "sending". ⚠️ Deploy server before shipping the iOS build.
- **Offline task deletions survive an app kill** — the delete-retry buffer persists to UserDefaults and restores on launch.
- **HomeView dead code deleted** (~150 lines: `summaryLine`, `topPriority`, `topPriorityRow`, `HomeTopPriority`).

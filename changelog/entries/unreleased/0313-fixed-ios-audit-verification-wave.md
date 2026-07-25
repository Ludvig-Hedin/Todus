---
id: 0313
title: "Fixed — iOS audit verification wave"
status: unreleased
category: Fixed
release_date: 2026-07-08
source: CHANGELOG.md
---

### Fixed — iOS audit verification wave, 2026-07-08

Three adversarial verifier agents re-checked every fix from the two audit waves (all other items confirmed correct). Findings, all fixed:

- **Inbox server-search fix was inert** — `serverSearchQuery` was declared and read but never assigned (the original fixer agent died mid-task), so server results were still re-filtered against the local subject/from/snippet blob. The debounce task now marks resolved server results as authoritative for the active query (guarded against the query changing mid-flight), making body-text search matches actually appear.
- Compose HTML-passthrough detection false-positived on plain text containing `<p`-like substrings (e.g. `i<processes`) and shipped it unescaped — now requires a real HTML tag.
- Global search kept the previous query's server email hits visible for the ~400ms until the new search landed — cleared on each new search.
- Attachment base64 decode + disk write moved off the main actor (multi-MB attachments hitched the UI).
- Month view could render a same-instant timed event twice on its day (the multi-day loop and the zero-duration fallback both fired) — fallback now keys off the day boundary.
- Removing an attachment that was added in the same editing session leaked the file on disk (it was in neither the persisted set nor the final set) — session-added files are now deleted immediately on remove.
- AI inline-compose autosave could double-fire `update_draft` when the card disappeared inside the debounce window (the `MainActor.run` await released the actor between check and clear) — the pending-save guard moved inside the actor-isolated block.
- Resolved the last three `TODO(bug-hunt)` markers: hidden Google calendars can no longer briefly reappear on cold start (connections with hidden calendars are skipped until their calendar list loads); the MLX coalesced-load cancellation race retries a fresh load instead of surfacing a foreign `CancellationError`; one stale historical marker rewritten as a NOTE.

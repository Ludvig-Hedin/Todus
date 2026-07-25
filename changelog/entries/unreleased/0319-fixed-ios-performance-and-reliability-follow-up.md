---
id: 0319
title: "Fixed — iOS performance and reliability follow-up"
status: unreleased
category: Fixed
release_date: 2026-07-22
source: CHANGELOG.md
---

### Fixed — iOS performance and reliability follow-up, 2026-07-22

- iOS task create/update/delete sync now uses the authenticated `tasks.sync` tRPC backend instead of the unconfigured legacy Supabase transport. Signed-in and pull-to-refresh flows hydrate paginated `tasks.list` results after folders, preserving pending local edits; explicit `tasks.deleted` tombstones remove cross-device deletions without inferring from page absence, stale offline upserts cannot resurrect them, and reminder/notification mirrors are cleaned only after SwiftData commits. Pending journals and in-flight pulls are invalidated on account changes. Priority changes sync from every task surface, and network/backend failures retain local work instead of deleting it.
- Automatic session expiry now runs the same account cleanup as manual sign-out. Tasks, folders, drafts, compose autosaves, AI history, caches, and pending mutations cannot leak into the next account; AI history reloads from the signed-in account after authentication.
- Mail compose now honors a server `{ success: false }` response, keeps the draft open, and serializes attachments off the main actor. Missing attachments stop the send instead of silently sending without them.
- Cold-launch URLs and notification actions wait for deferred app initialization. AI notification taps load the requested saved conversation, and the in-app voice sheet now shares the microphone mutex with Shortcut voice sessions.
- Reminder saves that race a local deletion remove the orphaned reminder, transient EventKit failures keep stable identifiers for retry, Calendar folder mappings no longer discard events outside a one-year window, stale Google Calendar refreshes cannot repopulate a disconnected account, and local-model cancel/restart attempts cannot overwrite each other.
- Reopened AI chats preserve their conversation identity on autosave. Voice text, audio, and tool-response transport failures surface as session errors instead of being presented as successful turns.
- Camera, photo-library, and pasted attachments now decode, JPEG-encode, and write off the main thread across Create, task details, AI chat, and mail compose, removing full-resolution image hitches from every attachment flow.
- Docs title saves are serialized and deduplicated so focus loss, debounce, Return, and navigation cannot race an older rename over the newest title. The docs tree now indexes children once per data change instead of filtering and sorting the full collection for every node.
- Google Calendar list/event endpoints now follow bounded pagination, and iOS keeps cached calendar sources during transient refresh failures instead of making calendars disappear.
- Local-model availability now reflects real Apple Intelligence runtime availability, device probes are cached, and deleting a model during launch scanning can no longer resurrect its installed state.
- Email thread decoding tolerates a malformed optional `latest` preview while preserving valid messages; local notification scheduling failures are logged; required Home tab rows can no longer be dragged into a snap-back move.
- Calendar edit saves now cross the serial EventKit queue without a Swift 6 non-Sendable capture warning.
- Native overflow navigation now uses real system More destinations, so Docs and Meetings no longer open as blank hidden tabs; Settings is a first-class overflow destination. Speech completion callbacks are synchronized and main-actor delivered without Swift 6 warnings.
- Task capture is local-first: no remote rejection removes a task the user created; failed sync remains visible and retries.
- Task and folder mutations now commit to SwiftData before creating Reminders, notifications, or backend mutations. Failed saves roll back locally instead of producing orphaned remote state, folder create/edit/delete failures stay visible for retry, and case-insensitive rename collisions are rejected.
- Scheduled-email queue deliveries now retry a transient missing payload only inside the retained send window, then terminate cleanly instead of exhausting retries for an already-cancelled message.
- macOS task/folder journals are bound to their account container and generation, so sign-out or account switching cannot replay stale in-flight work into another account; offline folder changes now use the durable sync journal before any network await.

---
id: 0192
title: "iOS follow-up resolution"
status: done
tags: [ios, performance, code-review-backlog]
files: [docs/audits/performance-reliability-audit-2026-07-22.md]
created: 2026-07-22
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Performance and reliability audit — 2026-07-22

## iOS follow-up resolution

The iOS-focused follow-up closed the remaining safe, code-proven native findings:

- bounded Google Calendar pagination now loads every page up to a 20-page safety cap;
- transient calendar-list refresh failures preserve the last good source list;
- camera image encoding/disk writes run off the main thread;
- docs hierarchy lookup is indexed and title mutations are serialized;
- malformed optional email previews no longer reject valid threads;
- local-model runtime detection, launch-scan deletion races, and repeated device probes are fixed;
- notification scheduling failures are observable, EventKit background saves are Swift 6-clean,
  speech completion callbacks are synchronized, and required tab rows cannot enter a confusing snap-back drag;
- Docs, Meetings, and Settings now use real native More destinations instead of hidden tab content that could render blank.
- cross-device task deletions now use explicit server tombstones, stale offline upserts cannot resurrect them,
  and reminder/notification mirrors are cleaned only after the local deletion commits.

Verified with 127 iOS unit tests, focused server pagination/scheduled-mail/task-sync tests, file-scoped ESLint,
an iOS simulator build, and all 10 native UI tests on a dedicated simulator. Historical finding tables below
are retained as audit evidence; their iOS rows are superseded by this resolution note.

The P1 fixes are implemented and verified. These remaining items need a deliberate
storage or routing design and were not hidden behind a risky local patch:

- **P2 — protected-route auth:** consolidate repeated session loaders under a cached
  parent route and distinguish an unavailable auth service from a logged-out session.
- **P2 — macOS decode work:** move large mail/docs JSON decoding off the main actor,
  then profile with Instruments before changing additional actor boundaries.
- **P2 — macOS legacy local-data recovery:** provide an explicit recovery/export flow
  for the retained pre-scoping SwiftData store and mutation journals. They cannot be
  safely assigned to an account automatically because the old records have no owner.
- **P3 — mail-send idempotency:** replace KV get/put dedupe with a strongly consistent
  reservation plus provider outcome record.
- **P3 — atomic claims:** make OTP consumption and AI credit reservation atomic and
  idempotent in the primary data store.

These are tracked in the full audit at
`docs/audits/performance-reliability-audit-2026-07-22.md`.

---

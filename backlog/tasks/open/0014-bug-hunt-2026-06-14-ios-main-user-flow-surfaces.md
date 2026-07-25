---
id: 0014
title: "Bug Hunt — 2026-06-14 (iOS main user-flow surfaces)"
status: open
priority: P3
tags: [ios, bug-hunt, code-review-backlog]
files: []
created: 2026-06-14
source: CODE_REVIEW_BACKLOG.md
---

> Section overview — the individual findings from this section are separate items.

# Bug Hunt — 2026-06-14 (iOS main user-flow surfaces)

Scoped bug review of the iOS app's main-flow surfaces (auth, email, tasks, calendar, AI/voice, home/create, docs/meetings, sync). Method: 10 parallel finders → adversarial verifier per candidate (default-skeptic, re-read the real code). 14 candidates → 8 confirmed real, 5 refuted as false positives. 6 confirmed bugs auto-fixed (small, unambiguous, no-regression); 1 confirmed bug flagged for human review (needs UX decision); the rest investigated and downgraded. Not yet compiled in this environment — `xcodebuild` validation pending.

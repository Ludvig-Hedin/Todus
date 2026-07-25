---
id: 0028
title: "Needs human review (verified real, deferred — higher-risk / unvalidatable under `--ui-testing` / product calls)"
status: open
priority: P3
tags: [ios, bug-hunt, code-review, code-review-backlog]
files: []
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Bug Hunt — 2026-06-08 — iOS email surface (`/bug-hunt`)

> Section overview — the individual findings from this section are separate items.

## Needs human review (verified real, deferred — higher-risk / unvalidatable under `--ui-testing` / product calls)

> Perf note: EM-1..EM-3 + EM-7 are the real performance cost on a fast-scrolling, real-account inbox. They were **not** auto-fixed because they touch the image-loading pipeline / require profiling against real mail, and the `--ui-testing` harness has no email data to validate against. Recommend a dedicated avatar-pipeline pass (downsample + disk-cache + candidate cap) with Instruments on a real account.

---

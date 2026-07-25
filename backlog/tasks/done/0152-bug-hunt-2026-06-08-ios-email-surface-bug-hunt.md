---
id: 0152
title: "Bug Hunt — 2026-06-08 — iOS email surface (`/bug-hunt`)"
status: done
tags: [ios, bug-hunt, code-review-backlog]
files: [Services/Email/EmailService.swift]
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

# Bug Hunt — 2026-06-08 — iOS email surface (`/bug-hunt`)

_Closed by the 2026-06-13 backlog resolution pass (`CODE_REVIEW_BACKLOG.md` → "No open code defects remain": every code-defect item was fixed, built, tested and committed in passes 1-6). Re-open if this finding is still reproducible._


Deep hunt across `Features/Email/*` + `Services/Email/EmailService.swift`, run by 4 parallel read-only audit agents (service logic, inbox/rows + perf, thread/compose, avatars/perf). Every finding re-verified against current source (several earlier "deferred" items were already fixed by parallel work and dropped). Build green before + after fixes.

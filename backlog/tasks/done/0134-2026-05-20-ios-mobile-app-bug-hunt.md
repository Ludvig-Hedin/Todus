---
id: 0134
title: "2026-05-20 — iOS Mobile App Bug Hunt"
status: done
tags: [ios, bug-hunt, code-review-backlog]
files: []
created: 2026-05-20
source: CODE_REVIEW_BACKLOG.md
---

# 2026-05-20 — iOS Mobile App Bug Hunt

_Closed by the 2026-06-13 backlog resolution pass (`CODE_REVIEW_BACKLOG.md` → "No open code defects remain": every code-defect item was fixed, built, tested and committed in passes 1-6). Re-open if this finding is still reproducible._


Scope: main user flows (auth, email, AI chat, tasks, calendar, network) in `apps/ios/Todus/Todus/`. 6 parallel investigators reviewed services + feature views. Findings below have been *verified by reading the cited line ranges* — speculative investigator claims that did not survive verification are listed separately at the bottom so they don't get re-investigated.

---
id: 0077
title: "Needs attention (not auto-fixed)"
status: open
priority: P3
tags: [bug-hunt, code-review-backlog]
files: []
created: 2026-06-01
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-01 — Bug hunt (uncommitted + last 3 commits)

> Section overview — the individual findings from this section are separate items.

## Needs attention (not auto-fixed)

> Note: the iOS sub-agent flagged `TodosAPIClient.swift:384 isUITestingSession` as an undefined-symbol build break — **false positive**. It is defined `public` in `packages/swift-auth/Sources/TodusAuth/AuthService.swift:88`; the agent only searched `apps/ios`. No action needed.

---

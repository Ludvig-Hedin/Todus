---
id: 0038
title: "EM-10 — A stale fromConnectionId (connection removed) silently flatMaps to nil → sends from the default mailbo"
status: open
priority: P3
tags: [ios, bug-hunt, code-review, code-review-backlog]
files: [EmailComposeView.swift]
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Bug Hunt — 2026-06-08 — iOS email surface (`/bug-hunt`) → Needs human review (verified real, deferred — higher-risk / unvalidatable under `--ui-testing` / product calls)

| ID | Area | Where | Sev | Problem | Suggested fix |
|----|------|-------|-----|---------|---------------|
| EM-10 | Email | `EmailComposeView.swift` (`fromConnectionId` resolve at send) | 🟡 med | A stale `fromConnectionId` (connection removed) silently `flatMap`s to nil → sends from the default mailbox without warning. | Validate the id still exists; warn if it resolved to nil. |

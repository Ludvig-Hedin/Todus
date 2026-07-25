---
id: 0037
title: "EM-9 — Archiving/deleting the currently-open thread doesn't clear selectedThreadId; detail can dangle on a rem"
status: open
priority: P3
tags: [ios, bug-hunt, code-review, code-review-backlog]
files: []
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Bug Hunt — 2026-06-08 — iOS email surface (`/bug-hunt`) → Needs human review (verified real, deferred — higher-risk / unvalidatable under `--ui-testing` / product calls)

| ID | Area | Where | Sev | Problem | Suggested fix |
|----|------|-------|-----|---------|---------------|
| EM-9 | Email | `EmailInboxView.swift:298` | 🟡 med (low conf) | Archiving/deleting the currently-open thread doesn't clear `selectedThreadId`; detail can dangle on a removed thread when triggered from elsewhere. | Clear `selectedThreadId` if its id vanished from `threads`. |

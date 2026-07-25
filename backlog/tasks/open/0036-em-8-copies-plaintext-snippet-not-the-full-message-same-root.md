---
id: 0036
title: "EM-8 — Copies plainText (snippet) not the full message — same root as the Forward bug."
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
| EM-8 | Email | `EmailThreadView.swift:1761-1777` ("Copy message text"/"Copy as quote") | 🟡 med | Copies `plainText` (snippet) not the full message — same root as the Forward bug. | Needs an HTML→plaintext helper; convert `message.body`. |

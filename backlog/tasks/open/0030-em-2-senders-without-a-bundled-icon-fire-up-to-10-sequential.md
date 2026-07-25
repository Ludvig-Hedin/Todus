---
id: 0030
title: "EM-2 — Senders without a bundled icon fire up to 10 sequential favicon GETs per row while scrolling."
status: open
priority: P2
tags: [ios, bug-hunt, code-review, code-review-backlog]
files: []
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Bug Hunt — 2026-06-08 — iOS email surface (`/bug-hunt`) → Needs human review (verified real, deferred — higher-risk / unvalidatable under `--ui-testing` / product calls)

| ID | Area | Where | Sev | Problem | Suggested fix |
|----|------|-------|-----|---------|---------------|
| EM-2 | Email perf | `SenderAvatarView.swift:539-589` | 🟠 high | Senders without a bundled icon fire **up to ~10 sequential favicon GETs per row** while scrolling. | Cap candidate URLs; prefer cached/known-good; drive from `.task` not phase `.onAppear`. |

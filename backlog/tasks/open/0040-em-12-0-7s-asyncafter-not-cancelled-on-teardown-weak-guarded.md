---
id: 0040
title: "EM-12 — 0.7s asyncAfter not cancelled on teardown (weak-guarded so safe, just wasteful)."
status: open
priority: P4
tags: [ios, bug-hunt, code-review, code-review-backlog]
files: []
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Bug Hunt — 2026-06-08 — iOS email surface (`/bug-hunt`) → Needs human review (verified real, deferred — higher-risk / unvalidatable under `--ui-testing` / product calls)

| ID | Area | Where | Sev | Problem | Suggested fix |
|----|------|-------|-----|---------|---------------|
| EM-12 | Email | `EmailThreadView.swift:2114` (webView `measureHeight`) | 🔵 low | 0.7s `asyncAfter` not cancelled on teardown (weak-guarded so safe, just wasteful). | Track a `DispatchWorkItem`; cancel in `dismantleUIView`. |

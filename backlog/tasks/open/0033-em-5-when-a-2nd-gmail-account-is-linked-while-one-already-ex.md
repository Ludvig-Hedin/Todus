---
id: 0033
title: "EM-5 — When a 2nd (Gmail) account is linked while one already exists, returns true without verifying the new c"
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
| EM-5 | Email | `Services/Email/EmailService.swift:1406-1425` (`connectGmail`, multi-account) | 🟠 high (med conf) | When a 2nd (Gmail) account is linked while one already exists, returns `true` without verifying the new connection row landed (`hasConnection` already true). | Re-`checkConnection(force:true)` and confirm the Gmail email is present before reporting success. |

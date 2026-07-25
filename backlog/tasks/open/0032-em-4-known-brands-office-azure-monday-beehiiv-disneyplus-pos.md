---
id: 0032
title: "EM-4 — Known brands (office/azure/monday/beehiiv/disneyplus/postmark/mailerlite/braintree) have slug == nil →"
status: open
priority: P2
tags: [ios, bug-hunt, code-review, code-review-backlog]
files: [Features/Email/SenderIconRegistry.swift]
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Bug Hunt — 2026-06-08 — iOS email surface (`/bug-hunt`) → Needs human review (verified real, deferred — higher-risk / unvalidatable under `--ui-testing` / product calls)

| ID | Area | Where | Sev | Problem | Suggested fix |
|----|------|-------|-----|---------|---------------|
| EM-4 | Email | `Features/Email/SenderIconRegistry.swift` (letter-only entries) | 🟠 high | Known brands (office/azure/monday/beehiiv/disneyplus/postmark/mailerlite/braintree) have `slug == nil` → early-return to gray initials, never try a favicon, and `spec.letter` is dead. They look worse than unknown senders. | Drop letter-only entries (fall through to favicon waterfall) OR render `spec.letter` on `spec.background`. |

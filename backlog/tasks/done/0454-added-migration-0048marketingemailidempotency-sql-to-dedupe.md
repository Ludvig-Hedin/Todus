---
id: 0454
title: "Added migration 0048marketingemailidempotency.sql to dedupe duplicate account rows before enforcing"
status: done
tags: [task-md, sprint]
files: [0048_marketing_email_idempotency.sql]
created: unknown
source: TASK.md
---

> Source context: TASK.md → Investigate onboarding/marketing email spam

- Added migration `0048_marketing_email_idempotency.sql` to dedupe duplicate account rows before enforcing the new auth account uniqueness constraint.

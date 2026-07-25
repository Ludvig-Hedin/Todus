---
id: 0452
title: "Root cause traced to non-atomic onboarding campaign enrollment in apps/server/src/lib/auth.ts plus m"
status: done
tags: [task-md, sprint]
files: [apps/server/src/lib/auth.ts]
created: unknown
source: TASK.md
---

> Source context: TASK.md → Investigate onboarding/marketing email spam

- Root cause traced to non-atomic onboarding campaign enrollment in `apps/server/src/lib/auth.ts` plus missing uniqueness on `mail0_account(provider_id, account_id)`.

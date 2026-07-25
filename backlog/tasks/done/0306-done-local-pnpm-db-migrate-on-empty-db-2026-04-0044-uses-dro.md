---
id: 0306
title: "DONE Local pnpm db:migrate on empty DB (2026-04): 0044 uses DROP INDEX IF EXISTS for meetintegration"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → Current Web/Server Fix Batch

- `DONE` **Local `pnpm db:migrate` on empty DB (2026-04):** `0044` uses `DROP INDEX IF EXISTS` for `meet_integration_user_id_idx` and does not duplicate `0043` recall uniques; `0049` trimmed to default `ALTER TABLE` only (no duplicate `0046`–`0048` DDL). Fresh setup: `createdb todus`, then `pnpm db:migrate`.

---
id: 0266
title: "Server — folder schema, summary query, generative UI docs"
status: archived
category: Docs
release_date: 2026-04-26
source: CHANGELOG.md
---

## [2026-04-26] Server — folder schema, summary query, generative UI docs

- [Schema] **`task_folder.updated_at`** now uses Drizzle `.$onUpdate(() => new Date())` so ORM-driven updates refresh the timestamp like other tables.
- [Schema] **`folder_item`** gains composite index `(folder_id, position)` for folder content ordered by position; migration `0053_needy_ben_urich.sql`.
- [Performance] **`folders.summary`** uses `COUNT(*) … GROUP BY` for per-folder task, chat, and folder-item totals and `ROW_NUMBER() … <= 3` subqueries for recent rows instead of loading all matching rows.
- [Docs] **Generative UI contract** — `SuggestionsCard` params documented to match `Button.actionParams` (string values only; JSON-stringify structured data).
- [Files] `apps/server/src/db/schema.ts`, `apps/server/src/db/migrations/0053_needy_ben_urich.sql`, `apps/server/src/trpc/routes/tasks.ts`, `apps/server/src/lib/generative-ui-contract.ts`, `CHANGELOG.md`

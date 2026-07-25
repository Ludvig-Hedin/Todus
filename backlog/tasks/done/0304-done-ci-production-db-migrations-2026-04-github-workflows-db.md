---
id: 0304
title: "DONE CI production DB migrations (2026-04): .github/workflows/db-migrate-production.yml runs server"
status: done
tags: [task-md, sprint]
files: [.github/workflows/db-migrate-production.yml]
created: unknown
source: TASK.md
---

> Source context: TASK.md → Current Web/Server Fix Batch

- `DONE` **CI production DB migrations (2026-04):** `.github/workflows/db-migrate-production.yml` runs server Drizzle migrate using GitHub secret `PRODUCTION_DATABASE_URL` (Hyperdrive origin / direct Postgres). Manual dispatch or push to `main` that touches `apps/server` migrations. Required for live Docs after schema changes.

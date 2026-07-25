---
id: 0271
title: "DONE Docs production schema repair (2026-04): /admin/run-migrations now idempotently creates mail0do"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → macOS UI

- `DONE` **Docs production schema repair (2026-04):** `/admin/run-migrations` now idempotently creates `mail0_doc_workspace`, `mail0_doc`, docs FKs/indexes, and `mail0_doc.is_starred` through the production Hyperdrive connection; `mode=info` includes docs table columns for verification. Deploy backend, then run the admin repair or the standard production Drizzle migration flow.

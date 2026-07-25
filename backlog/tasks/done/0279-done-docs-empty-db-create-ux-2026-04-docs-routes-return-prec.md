---
id: 0279
title: "DONE Docs empty DB + create UX (2026-04): docs routes return PRECONDITIONFAILED with a clear message"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → macOS UI

- `DONE` **Docs empty DB + create UX (2026-04):** `docs` routes return `PRECONDITION_FAILED` with a clear message when `mail0_doc` / `mail0_doc_workspace` tables are missing (instead of 500). macOS: visible **New document** in toolbar, sidebar, and empty state; tRPC error `message` shown in alerts and in `lastError` via `APIError` body parsing. Ops: apply doc migrations from `0044` onward on the server.

---
id: 0236
title: "Fix — Docs: missing DB tables + macOS create affordance"
status: archived
category: Docs
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Fix — Docs: missing DB tables + macOS create affordance

- [Fix] **Backend:** `docs.*` and `docs.workspaces.*` now map Postgres “relation does not exist” for doc tables to `PRECONDITION_FAILED` with a clear message instead of an opaque HTTP 500.
- [UX] **macOS:** Docs shows **New document** in the All docs toolbar, a **+** in the My space header, and a primary **New document** in the empty state; creating surfaces tRPC error text (e.g. migration hint) in an alert. `TodosAPIClient` surfaces tRPC `error.json.message` for failed HTTP responses app-wide.
- [Ops] Production must include doc tables from migration `0044_pale_luminals.sql` (and later doc migrations). Until then, the app explains that Docs storage is not available until migrations are applied.
- **Files:** `apps/server/src/trpc/routes/docs.ts`, `apps/macos/TodusMac/Services/API/TodosAPIClient.swift`, `apps/macos/TodusMac/Services/Docs/MacDocsService.swift`, `apps/macos/TodusMac/Views/Docs/MacDocsShellView.swift`

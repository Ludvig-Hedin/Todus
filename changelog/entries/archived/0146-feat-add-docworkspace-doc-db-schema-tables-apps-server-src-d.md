---
id: 0146
title: "Feat — Add docWorkspace + doc DB schema tables (apps/server/src/db/schema.ts)"
status: archived
category: Docs
release_date: 2026-04-01
source: CHANGELOG.md
---

## [2026-04-01] Feat — Add docWorkspace + doc DB schema tables (apps/server/src/db/schema.ts)

Added two new Drizzle ORM tables for the Docs feature:

- `mail0_doc_workspace` — user-owned workspace container with optional emoji, createdAt/updatedAt
- `mail0_doc` — Notion-style page with self-referential parentId for nesting, Tiptap JSONContent storage, plaintext search mirror, cross-entity link columns, and three indexes
  Added `import type { AnyPgColumn }` to satisfy TypeScript's circular reference check on the self-referential FK.
  Migration NOT applied — run `pnpm db:generate && pnpm db:migrate` to apply.

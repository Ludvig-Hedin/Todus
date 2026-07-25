---
id: 0278
title: "DONE Native Docs (2026-04): Replaced full-page web WKWebView with a Craft-style native shell (MacDoc"
status: done
tags: [task-md, sprint]
files: [0051_doc_starred_and_move.sql, TodusMac/MacDocsView.swift]
created: unknown
source: TASK.md
---

> Source context: TASK.md → macOS UI

- `DONE` **Native Docs (2026-04):** Replaced full-page web `WKWebView` with a Craft-style native shell (`MacDocsShellView`: sidebar, grid/list, editor). Rich body uses bundled Tiptap (`Resources/DocEditor`, built from `packages/macos-doc-editor`) + `TiptapDocEditorWebView` / `todusDoc` bridge; `MacDocsService` + tRPC. Backend: `doc.is_starred`, `docs.update` optional `parentId` / `workspaceId` / `isStarred` (migration `0051_doc_starred_and_move.sql`). Removed orphan `TodusMac/MacDocsView.swift` at repo root.

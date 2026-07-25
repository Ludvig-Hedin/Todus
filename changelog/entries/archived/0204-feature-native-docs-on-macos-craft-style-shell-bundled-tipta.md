---
id: 0204
title: "Feature — Native Docs on macOS (Craft-style shell + bundled Tiptap)"
status: archived
category: Docs
release_date: 2026-04-24
source: CHANGELOG.md
---

## [2026-04-24] Feature — Native Docs on macOS (Craft-style shell + bundled Tiptap)

- [Feature] **macOS:** The Docs tab no longer embeds the full web app in `WKWebView` (which could not use native `Authorization` for `clientLoader`). It is now a **native** shell: sidebar (workspaces, tree, starred, new page), **All docs** with grid/list + search, and a full-screen **editor** with title, star, breadcrumb, and a **bundled** Tiptap page loaded from `file://` (`Resources/DocEditor`). Swift injects initial JSON and receives debounced `onUpdate` via `WKScriptMessageHandler` (`todusDoc`); saves go through `docs.*` tRPC. Format strip: bold, italic, H1/H2, lists, task list (JS bridge to `window.todusEditor.run`).
- [Feature] **Backend:** `mail0_doc.is_starred` (default false). `docs.update` accepts optional `parentId`, `workspaceId`, and `isStarred` with workspace ownership checks for moves. Migration `0051_doc_starred_and_move.sql`.
- [Build] **Monorepo:** `packages/macos-doc-editor` builds with esbuild; output is copied to `TodusMac/Resources/DocEditor` for the Xcode bundle. Rebuild after editor changes: `pnpm --filter @zero/macos-doc-editor build` (or the package’s `package.json` name if different).
- [Cleanup] Removed duplicate `TodusMac/MacDocsView.swift` at the `TodusMac` folder root; `MacDocsView` lives under `Views/Docs/`.
- **Files:** `apps/server/src/db/schema.ts`, `apps/server/src/db/migrations/0051_doc_starred_and_move.sql`, `apps/server/src/trpc/routes/docs.ts`, `packages/macos-doc-editor/`, `apps/macos/TodusMac/Resources/DocEditor/`, `apps/macos/TodusMac/Domain/MacDocTypes.swift`, `apps/macos/TodusMac/Services/Docs/MacDocsService.swift`, `apps/macos/TodusMac/Views/Docs/*.swift`, `apps/macos/TodusMac/App/MacAppServices.swift`, `apps/macos/TodusMac.xcodeproj/project.pbxproj`

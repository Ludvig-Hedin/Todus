---
id: 0229
title: "UX — Docs: clear errors when storage isn’t ready (web + macOS)"
status: archived
category: Docs
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] UX — Docs: clear errors when storage isn’t ready (web + macOS)

- [UX] **Mail + Web:** `DocTree` no longer auto-creates a workspace or stays on skeletons when `docs.workspaces.list` fails (e.g. `PRECONDITION_FAILED` / missing doc tables). Sidebar shows the server message and **Retry**; landing page shows the same message instead of a broken “New page” action.
- [UX] **macOS:** All-docs pane shows **Couldn’t load docs** with the API message and **Retry** when load failed and the list is empty (instead of “No pages yet”). Toolbar **New document** is disabled until a successful refresh when in that error state.
- **Files:** `apps/mail/components/docs/doc-tree.tsx`, `apps/web/components/docs/doc-tree.tsx`, `apps/mail/app/(routes)/mail/docs/page.tsx`, `apps/web/app/(routes)/mail/docs/page.tsx`, `apps/macos/TodusMac/Views/Docs/MacDocsShellView.swift`

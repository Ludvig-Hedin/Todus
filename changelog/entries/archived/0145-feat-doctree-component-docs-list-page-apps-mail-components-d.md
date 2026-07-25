---
id: 0145
title: "Feat — DocTree component + Docs list page (apps/mail/components/docs/doc-tree.tsx, apps/mail/app/(routes)/mail/docs/page.tsx)"
status: archived
category: Docs
release_date: 2026-04-01
source: CHANGELOG.md
---

## [2026-04-01] Feat — DocTree component + Docs list page (apps/mail/components/docs/doc-tree.tsx, apps/mail/app/(routes)/mail/docs/page.tsx)

Added `DocTree` sidebar component and replaced the `DocsPage` stub with a real two-column layout:

- `DocTree` — fetches workspaces via `trpc.docs.workspaces.list`, fetches root docs per workspace via `trpc.docs.list`, renders collapsible workspace sections with inline "new page" (+ icon) and "new workspace" buttons; loading skeletons; empty state.
- `DocsPage` — `ResizablePanelGroup` layout: left panel (20% default, 15% min) hosts `DocTree`; right panel shows an empty-state with "Select a page to start reading" + "New page" button; auth-guarded via `clientLoader`.

---
id: 0223
title: "DONE Documents/Notes native shell (iOS) — Domain/DocTypes.swift (DTOs mirroring macOS), Services/Doc"
status: done
tags: [task-md, sprint]
files: [Domain/DocTypes.swift, Services/Docs/DocsService.swift, Features/Docs/DocsListView.swift, Features/Docs/DocEditorView.swift]
created: 2026-05-17
source: TASK.md
---

> Source context: TASK.md → Current iOS Parity + Hardening Sprint (2026-05-17)

- `DONE` **Documents/Notes native shell (iOS)** — `Domain/DocTypes.swift` (DTOs mirroring macOS), `Services/Docs/DocsService.swift` (refresh/list/create/update/delete/move/star/togglePin/search, auto-creates Personal workspace), `Features/Docs/DocsListView.swift` (NavigationSplitView on iPad, NavigationStack on iPhone, recursive nested rows, pull-to-refresh, context menu, swipe actions, empty state), `Features/Docs/DocEditorView.swift` (thin native nav wrapper around existing `DocsWebView`). `DocsWebView` gained optional `docId` param for deep linking; legacy callers unchanged. `MoreSheetView` exposes native Docs + "Docs (Web)" fallback.

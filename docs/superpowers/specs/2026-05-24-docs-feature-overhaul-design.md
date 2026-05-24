# Docs Feature Overhaul — iOS Bug Fixes + Cross-Platform Polish

**Date:** 2026-05-24
**Goal:** Fix critical iOS bugs (tap doesn't open doc, + button creates but doesn't navigate) and bring iOS + macOS docs UX to Apple-Notes / Google-Docs level of polish and intuitiveness.

---

## Context

The docs feature exists across:

- **Backend** — `apps/server/src/trpc/routes/docs.ts` — workspaces + docs CRUD + search. Solid, no changes needed.
- **iOS** — `apps/ios/Todus/Todus/Features/Docs/` — `DocsListView`, `DocEditorView`, `DocsWebView` (`DocsBrowserView`).
  - `DocsService` (Observable) loads workspaces + all docs.
  - Editor body is a `WKWebView` loading `/mail/docs/<id>` from the deployed web app.
- **macOS** — `apps/macos/TodusMac/Views/Docs/` — `MacDocsShellView` (swap layout), `MacDocsAllPane` (grid/list), `MacDocsSidebarView`, `MacDocEditorPane` (native title + Tiptap WebView body + autosave).
- **Shared Tiptap editor** — `packages/macos-doc-editor` — bundled into macOS app under `Resources/DocEditor`. **Not bundled in iOS** (deferred — see Out of Scope).

---

## Confirmed Root-Cause Bugs (iOS)

### Bug 1 — Tap doc row doesn't navigate (iPhone)

**Location:** `apps/ios/Todus/Todus/Features/Docs/DocsListView.swift:71`

```swift
List(selection: $selectedDocID) {  // ← consumes tap on iPhone
    ForEach(...) {
        NavigationLink(value: doc.id) { ... }  // ← push suppressed
    }
}
```

On iPhone (`sizeClass != .regular`), the view is wrapped in `NavigationStack`. `List(selection:)` is meant for `NavigationSplitView` selection-driven detail pane (iPad). On iPhone it captures the tap as a selection change instead of letting `NavigationLink` push.

### Bug 2 — `+` button creates doc but doesn't open it (iPhone)

**Location:** `DocsListView.swift:264-273`

```swift
private func createDoc() async {
    ...
    let doc = try await services.docsService.createNewDocument()
    selectedDocID = doc.id  // ← only iPad NavigationSplitView observes this
}
```

iPhone `NavigationStack` has no programmatic push wired to `selectedDocID`. The selection mutates but the stack stays at the list.

---

## Design — What We're Building

### Phase 1 · iOS Bug Fixes (critical)

Rewrite `DocsListView` navigation:

- Introduce `@State private var path = NavigationPath()` for iPhone.
- iPhone: `NavigationStack(path: $path)`.
- iPad: keep `NavigationSplitView` with `selection: $selectedDocID`.
- Rows: replace `NavigationLink(value:)` with a `Button` whose action pushes onto `path` (iPhone) or sets selection (iPad). Branch by `sizeClass`.
- `createDoc()` after success: push `doc.id` onto `path` (iPhone) **or** set `selectedDocID` (iPad).
- Drop `List(selection:)` on iPhone — use plain `List` with button rows; keep selection binding only for iPad split view.

### Phase 2 · iOS List Polish (Apple-Notes feel)

- **Search bar** at top of list — debounced 250ms, filters across `title` + `contentText`. Mirror macOS filter logic.
- **"All documents" virtual section** at top of list — flat, sorted by `updatedAt desc`. Tapping any row pushes the editor.
- **Starred section** under "All documents" when `starredDocs` non-empty.
- **Workspace sections** below — same recursive outline as today but with cleaner spacing + selected-row highlight.
- **Empty state** — richer copy + "New document" button (already exists, polish only).
- **Smooth row animations** — explicit `withAnimation(Motion.fast)` on insert/delete so create doesn't pop.
- **Pull-to-refresh** — already exists, keep.
- **Toolbar** — `+` button keeps progress spinner during create. Add a search button (or always-visible `.searchable` modifier).

### Phase 3 · iOS Editor Native Chrome

Rewrite `DocEditorView` to mirror `MacDocEditorPane`'s shell pattern, **keeping `DocsBrowserView` (WKWebView) as the body**:

- Native `TextField` for title at top with autofocus when doc was just created (empty title detected → focus).
- Debounced title autosave (600ms after last keystroke) — calls `docsService.renameDoc`.
- **Save indicator** — idle/saving/saved/failed states with retry. Driven by title save state (body autosaves inside the web view today).
- **Star button** in toolbar.
- **Info menu** — share link + word count (when available via web bridge later; show "—" for now if not wired) + doc ID copyable.
- **Back button** — uses `dismiss()` on iPhone, falls back to "Docs" title on iPad split.

> Body editor stays `DocsBrowserView` for now. Bundling Tiptap into iOS is a separate project — see Out of Scope.

### Phase 4 · macOS Layout — Google Docs Style

Refactor `MacDocsShellView` from swap layout to **2-column persistent sidebar**:

```
┌──────────┬─────────────────────────────┐
│ Sidebar  │ Right pane                  │
│ (240px,  │ - List/grid when no doc     │
│ always   │ - Editor when doc selected  │
│ visible) │   (with back button header) │
└──────────┴─────────────────────────────┘
```

- Sidebar persists across all states. Use `HSplitView` with sidebar fixed and right pane flexible.
- Right pane switches between `MacDocsAllPane` (no doc) and `MacDocEditorPane` (doc selected).
- Editor pane already has a "All docs" back button — repurpose as the Google-Docs-style return to list.
- **Cmd+N** keyboard shortcut for `New document` (use `.keyboardShortcut("n", modifiers: .command)` on toolbar button).
- **Cmd+F** focuses the search field in the right pane.
- Sidebar entries get a `selected` visual treatment (filled background) when their doc matches `selectedDocId`.
- Sidebar "All documents" entry highlights when `selectedDocId == nil`.

### Phase 5 · macOS Card + Empty-State Polish

- **Doc cards** — larger title (15pt), 2-line content preview, relative timestamp at bottom, emoji + star inline with title.
- **Sort menu** in `MacDocsAllPane` header — Most recent / Alphabetical / Starred first.
- **Empty state** — richer illustration + primary CTA + secondary "Import" placeholder (no-op for now, hidden behind flag).
- **Loading state** — skeleton cards (4-6 placeholders) instead of bare spinner. Mirror MacHomeView's loading pattern.
- **Sidebar workspace "New page" inline link** — make it look less like a row, more like a quiet "+ new page" affordance.

### Phase 6 · Cross-Platform Polish + Bug Hunt + Inconsistency Sweep

- **`/inconsistency-hunter`** sweep on docs feature across web + iOS + macOS.
- **`/bug-hunt`** on `DocsService`, `MacDocsService`, `DocsListView`, `DocEditorView`, `MacDocsShellView`, `MacDocEditorPane`, `MacDocsAllPane`.
- **Motion tokens** — replace any `.snappy()` / `.easeOut()` with `Motion.fast/base` per design system.
- **Update docs:**
  - `CHANGELOG.md` — entry for the overhaul.
  - `TASK.md` — mark docs polish in progress / done.
  - `DESIGN_SYSTEM.md` if new patterns surface (likely no new tokens).
  - `DESIGN_SYSTEM_INCONSISTENCIES.md` if findings surface.

---

## Architecture Decisions

### Why keep `DocsBrowserView` (WebView) on iOS body

- Bundling Tiptap into iOS requires Xcode project surgery + a build script (mirror of macOS approach). Scope risk in a single session.
- Native chrome (title, save indicator, toolbar) gives the Apple-Notes feel without rewriting the editor surface.
- Defer full Tiptap bundle to a follow-up project.

### Why 2-column (not 3) on macOS

- User explicit preference: Google Docs style. Sidebar | editor, back button in header.
- Simpler layout, less state to coordinate.
- Cards/grid view lives in the right pane when no doc selected — same surface, different mode.

### Why NavigationPath (not selection-driven NavigationSplitView) on iPhone

- iPhone has no detail pane — `NavigationSplitView` collapses to a stack and selection semantics get awkward.
- `NavigationPath` is the canonical iOS 16+ pattern for programmatic push.
- iPad keeps `NavigationSplitView` because it has a real detail pane.

---

## Data / API Contract

No backend changes. All existing tRPC endpoints sufficient:

- `docs.list` — fetch all docs
- `docs.get` — single doc
- `docs.create` — create with optional `title`, `workspaceId`, `parentId`
- `docs.update` — patch any field
- `docs.delete`
- `docs.search`
- `docs.workspaces.{list,create,update,delete}`

---

## Files Changed

### iOS (modified)
- `apps/ios/Todus/Todus/Features/Docs/DocsListView.swift` — full rewrite of navigation, add search + starred + all-docs sections.
- `apps/ios/Todus/Todus/Features/Docs/DocEditorView.swift` — native chrome (title, save indicator, star, info, back).

### iOS (no change expected)
- `DocsService.swift` — service layer already exposes everything we need.
- `DocsWebView.swift` — kept as body. (May add a "hide web title" flag later.)

### macOS (modified)
- `apps/macos/TodusMac/Views/Docs/MacDocsShellView.swift` — refactor from swap to persistent 2-column.
- `apps/macos/TodusMac/Views/Docs/MacDocEditorPane.swift` — toolbar/back button tweaks for Google-Docs feel.
- Possibly extract a new `MacDocsRightPane` to hold the switch between list and editor.

### Docs
- `CHANGELOG.md`
- `TASK.md`

---

## Out of Scope (Follow-up Projects)

- **Bundling Tiptap into iOS** — adds offline editing parity with macOS. Requires Xcode build phase + asset copy. Worth a separate spec.
- **Real-time collab** — Yjs / CRDT. Not in this overhaul.
- **Drag-to-reorder docs across workspaces** — backend supports order/parentId, but UI is a separate effort.
- **Doc templates** — empty state shows blank doc only.
- **Embeds (calendar event, task, thread links)** — backend has `linkedThreadId/EventId/TaskId` columns; UI does not surface them yet.

---

## Success Criteria

1. iPhone: tapping any doc row opens it in the editor.
2. iPhone: `+` button creates a doc and immediately opens it.
3. iPad: behavior unchanged.
4. iOS editor: native title editable, autosaves, save indicator visible.
5. iOS list: search works, starred section appears when applicable, "All documents" entry works.
6. macOS: sidebar always visible during edit; clicking back returns to list while sidebar stays.
7. macOS: Cmd+N creates a new doc and opens it.
8. macOS cards: visible content preview + relative time.
9. No regression in existing flows (create / rename / star / delete / share / refresh / search).
10. `/bug-hunt` + `/inconsistency-hunter` find nothing critical post-changes.
11. App builds, no Swift compile errors, no console errors at runtime.

---

## Risks

- **NavigationStack + List on iPhone tap recognition** — Swift sometimes makes button-in-list awkward. Mitigation: test on iPhone simulator before claiming done.
- **macOS layout regression** — refactoring HSplitView for persistent sidebar could break edge cases (resizing, fullscreen). Mitigation: keep current swap as fallback if HSplitView misbehaves; explicit window-width breakpoint for sidebar collapse on narrow.
- **Autosave race** — debounced title save + body autosave (web) writing to the same `updatedAt` could clobber each other's optimistic UI. Mitigation: title save sets `title` only; body save sets `content` + `contentText` only — no overlap on partial-update endpoint (verified in `docs.update`).
- **Web `/mail/docs/<id>` already shows its own title field** — native title above would duplicate. Mitigation: hide web title via CSS injection in `DocsBrowserView`, or accept dual display and treat web title as fallback.

---

## Implementation Order

1. Phase 1 (iOS bug fixes) — un-block users immediately.
2. Phase 3 (iOS editor chrome) — native title + save indicator.
3. Phase 2 (iOS list polish) — search + starred + all-docs.
4. Phase 4 (macOS 2-col layout).
5. Phase 5 (macOS card polish).
6. Phase 6 (cross-cutting sweep).
7. Docs + commit.

---
id: 0299
title: "Docs review pass — UX polish, context menu parity, persistent saved badge"
status: archived
category: Docs
release_date: 2026-05-24
source: CHANGELOG.md
---

## [2026-05-24] Docs review pass — UX polish, context menu parity, persistent saved badge

Follow-up to the docs overhaul, driven by four review passes (review-current-implementation, ux-polish, ux-assesment, bug-hunt).

**iOS:**

- Web doc page now exposes `data-doc-page-title` + `data-doc-sidebar` attributes; iOS WKWebView CSS injection updated to actually match them (previous selectors were no-ops — duplicate title + double sidebar were visible on iPhone).
- Swipe-delete on iPhone now requires a `.confirmationDialog` confirmation — fat-finger no longer destroys data.
- Recent section excludes docs already in Starred to stop the same row appearing 3× in the same List.
- Compound `.id("recent-…")` / `.id("starred-…")` on flat rows so SwiftUI doesn't merge swipe/hover state between section appearances.
- iPad row highlight restored — active doc gets `Color.accentColor.opacity(0.12)` `listRowBackground` (was lost when `List(selection:)` was removed in the nav fix).
- Haptics on open / create / delete / star / rename, success + error.
- Rename alert Save button disabled when trimmed text empty; renameText cleared on dismiss.
- `.id(doc.id)` on `DocEditorView` at both entry points — switching docs no longer briefly shows the previous doc's title.
- Autofocus moved from `DispatchQueue.main.asyncAfter` to a cancellable `Task` stored in `@State`; cancelled in `flushPendingSave` to stop focus firing on torn-down views.
- `flushPendingSave` also cancels `savedRevertTask` + `autofocusTask` to avoid orphan timers writing to `@State`.
- Save indicator wrapped in `.frame(minWidth: 70, alignment: .trailing)` so the title edge doesn't shift on every keystroke.
- Share button gated on `shareURL != nil`.
- Dark-mode injection now listens for appearance changes (was one-shot at load).
- MoreSheet 'Docs' entry no longer pushes via NavigationLink (double-stacked Docs' own NavigationStack inside MoreSheet's); now uses `onNavigate(.docs)` + `dismiss()`, mirroring Calendar.

**macOS:**

- Context menu parity with iOS across **all** doc surfaces (sidebar outline rows, starred rows, doc cards, table list rows): Open / Rename / Star / Copy title / Delete with confirmation. Previously only Open + Copy title — there was literally no way to delete a doc from the macOS UI.
- `MacDocsService` gains `renameDoc(id:title:)` and `togglePin(id:)` wrappers mirroring iOS so callers don't construct full `DocUpdateInput` for the common cases.
- Removed inline per-workspace "New document" sidebar button — used `try?` + silently swallowed errors, and was the 4th create entry point. Header `+`, All-docs toolbar `+`, and Cmd+N cover it.
- Sidebar outline indentation now uses `.padding(.leading)` instead of literal whitespace (works with dynamic type + screen readers).
- Star indicator + `.help` tooltip added to sidebar rows; cards gain `.help` on long titles.
- Cmd+B / Cmd+I keyboard shortcuts in the format strip; `.help` + `.accessibilityLabel` on every format button via the new `tiptapButton(_:_:help:shortcut:)` signature.
- All-docs grid: sort-mode change animates via `Motion.base` so reorder transitions instead of snapping.

**Both platforms — persistent saved badge:**

- `markSaved` no longer auto-reverts to `.idle` after 2 seconds on iOS or macOS. The Saved checkmark stays visible until the next `.saving` transition — trust signal matches Google Docs' "All changes saved in Drive". The fade-out was a confidence regression.

**Pre-existing bug-hunt items deferred to backlog** (added to `CODE_REVIEW_BACKLOG.md`):

- Recursive `AnyView(Group)` outline pattern breaks SwiftUI identity / animation
- Recursive `docRow` / `docOutline` has no cycle protection against corrupt server data
- Debounce title save + flushPendingSave can theoretically race two requests
- `commitRename` fire-and-forget Task isn't owned by the view
- macOS no Cmd+F to focus search; macOS search disappears when editing; AI revert button parity gap on iOS; iOS no body autofocus after title submit; iOS no grid view; iOS no sort menu

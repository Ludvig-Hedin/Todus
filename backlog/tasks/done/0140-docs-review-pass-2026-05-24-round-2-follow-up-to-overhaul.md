---
id: 0140
title: "Docs review pass — 2026-05-24 (round 2, follow-up to overhaul)"
status: done
tags: [ios, bug-hunt, code-review, code-review-backlog]
files: []
created: 2026-05-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-20 — iOS Mobile App Bug Hunt

## Docs review pass — 2026-05-24 (round 2, follow-up to overhaul)

_Closed by the 2026-06-13 backlog resolution pass (`CODE_REVIEW_BACKLOG.md` → "No open code defects remain": every code-defect item was fixed, built, tested and committed in passes 1-6). Re-open if this finding is still reproducible._


### Auto-fixed (15+ items, see CHANGELOG `Docs review pass` entry)
Includes context-menu parity, persistent saved badge, web data attributes, iPad row highlight restore, MoreSheet double-stack fix, iOS haptics, swipe-delete confirmation, autofocus cancellable, save-indicator min-width, dark-mode listener, sort animation, sidebar indent via padding, Cmd+B / Cmd+I shortcuts, AppStorage self-heal comment.

### Needs human review / design call (8 items)

- **Recursive `AnyView(Group/VStack { row; ForEach(children) })` outline** (`DocsListView.swift:336-343` and `MacDocsShellView.swift:687-707`) — breaks SwiftUI identity; can cause hover/swipe state to bleed and re-render the whole nested subtree on changes. Refactor candidates: `OutlineGroup` with `KeyPath` children, or flatten so each row stands alone in its parent `ForEach`.
- **No recursion-depth/cycle guard in `docRow` / `docOutline`** (same files) — corrupt server data (`A.parentId == B.id`, `B.parentId == A.id`) stack-overflows. Add `visited: Set<String>` param.
- **Debounced title save + `flushPendingSave` race** (`DocEditorView.swift:flushPendingSave`) — both POST `renameDoc`. If network reorders, stale value wins. Centralize through a single Task chain, or have backend honor a client `updatedAt`.
- **`commitRename` Task is fire-and-forget** (iOS + macOS) — errors that surface after view teardown are lost. Move into service layer or store Task handle.
- **`sizeClass` change mid-tap on iPad** (`DocsListView.swift:open(docID:)`) — Stage Manager / slide-over resize between push and animation drops active doc. Sync `path` ↔ `selectedDocID` in `.onChange(of: sizeClass)`.
- **macOS Cmd+F search focus** — spec mentioned, not wired; macOS search field also disappears when an editor is open (right pane swap). Either move search to sidebar or keep a slim search above the editor.
- **iOS body autofocus after title `submitLabel(.done)`** — currently only dismisses the keyboard; Apple Notes drops cursor into body. Needs a `window.todusEditor.focus()` bridge call in `DocsBrowserView`.
- **iOS grid view + sort menu parity gap** — macOS has both, iOS has neither. Discussed in spec, intentionally deferred — flag in case it surfaces in user feedback.

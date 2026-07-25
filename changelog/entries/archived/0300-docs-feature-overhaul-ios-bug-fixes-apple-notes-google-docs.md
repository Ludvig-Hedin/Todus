---
id: 0300
title: "Docs feature overhaul — iOS bug fixes + Apple-Notes / Google-Docs polish (iOS + macOS)"
status: archived
category: Docs
release_date: 2026-05-24
source: CHANGELOG.md
---

## [2026-05-24] Docs feature overhaul — iOS bug fixes + Apple-Notes / Google-Docs polish (iOS + macOS)

**iOS bug fixes (critical, unblocks users):**

- Fix: tapping a doc row on iPhone now opens the editor. Root cause was `List(selection:)` on a `NavigationStack` swallowing taps before `NavigationLink` could push (selection is iPad-only). iPhone now uses `NavigationStack(path:)` with explicit `NavigationPath`; rows are buttons that push via `path.append(id)` (iPhone) or set `selectedDocID` (iPad).
- Fix: `+` button on iPhone now creates **and** opens the new doc. Previously it only mutated `selectedDocID`, which iPhone's stack does not observe — the doc was created on the server but the user stayed on the list.
- `MainTabView` no longer wraps `DocsListView` in an outer `NavigationStack` (the list owns its own nav via size-class branch; double-stacking was silently swallowing pushes).

**iOS polish (Apple-Notes feel):**

- Native title `TextField` with debounced (500ms) autosave + save indicator (idle / saving / saved / failed-with-retry). Mirrors `MacDocEditorPane` shell pattern.
- Title autofocuses on newly-created docs (empty / "Untitled") so the user can start typing immediately.
- `.searchable()` filters by title + `contentText`. Workspace sections hide during active search; flat "Results" section appears instead.
- New "Recent" (top 5 by `updatedAt`) and "Starred" sections in the list.
- Flat row variant shows a one-line content preview.
- Doc info sheet (created / updated / ID) + share link + copy title in `…` menu.
- Title save debounce now snapshots `titleDraft` at schedule time so a teardown-time flush can't race against the scheduled task.

**macOS polish (Google-Docs feel):**

- Persistent sidebar — sidebar is always visible in an `HSplitView`; right pane swaps between `MacDocsAllPane` (no doc selected) and `MacDocEditorPane` (doc selected). Previously the sidebar disappeared during edit.
- `Cmd+N` creates and opens a new doc from anywhere in the docs view (hidden `Button` + `.keyboardShortcut`).
- Sidebar entries (workspace outline rows, starred rows, "All documents") get a `MacTheme.accent.opacity(0.16)` fill when their target matches `selectedDocId`.
- New sort menu (Most recent / Alphabetical / Starred first) in the All-docs header, persisted via `@AppStorage`.
- Richer doc cards: 15pt semibold title with inline emoji, 12pt secondary preview (falls back to "Empty document"), 10pt muted relative timestamp, top-right yellow star, hover scale (1.01) via `Motion.fast`, selected accent border (1.5px).
- Skeleton loading state: 6 redacted cards in the same grid layout instead of a bare spinner.
- "New document" / "No documents yet" copy aligned with iOS (was "New page" / "No pages yet").

**Cross-platform consistency:**

- Title autosave debounce aligned to 500ms iOS↔macOS.
- One canonical term: "New document" everywhere (was mixed with "New page").
- Empty-state copy unified.

**Architecture notes:**

- iOS editor body still uses the `DocsBrowserView` WKWebView (loads `/mail/docs/<id>` from the web app). Bundling the Tiptap editor into iOS for offline parity is a deferred follow-up project documented in the spec.
- Web page's title row is hidden via injected CSS in `DocsWebView` so it doesn't duplicate the native iOS title. Selectors are forward-looking — harmless no-op if the web template doesn't expose them yet.
- Five pre-existing docs bugs (force unwraps in `MacDocEditorPane` AI revert, `WKNavigationDelegate` weak-self gaps, leaked `Task.sleep` timers, silent flush errors, Personal-workspace auto-create races) flagged in `CODE_REVIEW_BACKLOG.md` for follow-up.

**Files touched:**

- `apps/ios/Todus/Todus/Features/Docs/DocsListView.swift` (rewrite)
- `apps/ios/Todus/Todus/Features/Docs/DocEditorView.swift` (rewrite)
- `apps/ios/Todus/Todus/Features/Docs/DocsWebView.swift` (CSS injection)
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift` (drop outer NavigationStack)
- `apps/macos/TodusMac/Views/Docs/MacDocsShellView.swift` (layout refactor + sidebar selected state + sort menu + DocCardView + skeleton)
- `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift` (pre-existing EdgeInsets + type-checker fixes to unblock build verification)
- `CODE_REVIEW_BACKLOG.md` (5 follow-up entries)
- `TASK.md`
- Specs / plans: `docs/superpowers/specs/2026-05-24-docs-feature-overhaul-design.md`, `docs/superpowers/plans/2026-05-24-docs-feature-overhaul.md`

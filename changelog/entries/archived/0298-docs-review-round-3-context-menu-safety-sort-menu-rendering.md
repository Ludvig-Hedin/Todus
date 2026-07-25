---
id: 0298
title: "Docs review round 3 — context-menu safety, sort menu rendering, macOS title autofocus"
status: archived
category: Docs
release_date: 2026-05-24
source: CHANGELOG.md
---

## [2026-05-24] Docs review round 3 — context-menu safety, sort menu rendering, macOS title autofocus

Follow-up round (3rd review pass — review-current-implementation, ux-polish, ux-assesment, bug-hunt).

**iOS:**

- iPhone context-menu Delete now routes through the same confirmation dialog as swipe-delete (long-press → Delete was equally fat-fingerable).
- Tap haptic only fires when open actually changes state (no buzz for re-tap on selected iPad row).
- Title save: `CancellationError` + `URLError.cancelled` swallowed — debounce cancel storm no longer flashes "Save failed".
- Retry button no-op fixed: reverting the title to the last persisted value clears the `.failed` badge (was stuck).
- Removed dead `.navigationDestination` from the iPad branch (sidebar drives detail via `selectedDocID`, never pushes a `String`).
- Rename `TextField` got `.submitLabel(.done)` + `.onSubmit` — Return now confirms.
- Title `TextField` got `.textInputAutocapitalization(.sentences)`.
- Star toolbar foreground: unstarred = `.secondary` (was `.accentColor`, read as "active").
- Dropped dead `savedRevertTask` `@State` (no longer assigned after persistent-saved badge change).
- Dropped dead `if shareURL != nil` guard — `effectiveAppURL` is non-optional.

**iOS WebView:**

- Hide-chrome CSS injection dedupes via `document.querySelector('style[data-todus-native-chrome]')` — SPA back/forward navigation no longer accumulates `<style>` nodes.

**Web:**

- `saveTitle` normalizes empty/whitespace-only titles to `"Untitled"` before mutate — prevents titles silently disappearing across platforms (matches iOS native shell).
- Divider between title and editor body wrapped in `data-doc-page-title` so native iOS shell's CSS hides it together with the title row (previously left an orphan horizontal rule above the editor body).

**macOS:**

- Format strip `Cmd+B` / `Cmd+I` shortcut bindings dropped — Tiptap already owns these inside the focused WebView; double-binding either doubled the toggle or stole keystrokes from the native title.
- `tiptapButton` gains `.help` + `.accessibilityLabel` + `.disabled(wk == nil)` so format buttons can't fire before editor loads.
- Sort menu rewritten with `Picker` + `.inline` style inside `Menu` — previous `Button` + sibling checkmark image didn't render the active state in macOS Menus.
- Sidebar starred row context menu: Star/Unstar label conditional on `d.isStarred` (was hardcoded "Unstar") + adds `Copy title` for 4-way menu parity.
- Table list context menu adds `Copy title`; row gets `.help` on long titles; `Updated` column uses `.relative(presentation: .named)` to match grid card format.
- `starredFirst` sort comparator simplified.
- `flushPendingSave` skips when the doc was removed from `allDocs` (delete just landed) — no wasted update for a 404'd id.
- `flushPendingSave` + `saveTitle` normalize empty/whitespace title to `"Untitled"` for cross-platform parity.
- `saveTitle` swallows `CancellationError` + `URLError.cancelled`, clears stale `.failed` badge on no-op.
- Title debounce 600ms → 500ms (matches iOS).
- **New:** `titleFocused` `@FocusState`; `load()` autofocuses title when doc opens empty/Untitled — Apple-Notes parity with iOS (this was UX assessment's #1 macOS gap).
- Star toolbar button: dynamic `.help` / `.accessibilityLabel` (Star ↔ Unstar), foreground yellow when starred / `.secondary` otherwise, `.disabled(doc == nil)`.
- Info popover button `.disabled(doc == nil)`.
- Dropped dead `savedRevertTask` `@State`.

**Items deferred to backlog** (architectural / broader UX work):

- iOS body autofocus after title submit (needs JS bridge to Tiptap)
- macOS `Cmd+K` quick-open / global search persisted across views
- Clickable star on macOS cards/rows (broader interaction redesign)
- Info popover field divergence iOS↔macOS (Created/Updated vs Words/Chars)
- macOS `Cmd+W` to close editor (back chevron works today)
- Recursive `AnyView(Group)` outline → `OutlineGroup` refactor
- Recursive doc tree cycle guard

---
id: 0141
title: "Bug Hunt — 2026-05-24 — Docs feature overhaul"
status: done
tags: [ios, bug-hunt, code-review-backlog]
files: []
created: 2026-05-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-20 — iOS Mobile App Bug Hunt

## Bug Hunt — 2026-05-24 — Docs feature overhaul

_Closed by the 2026-06-13 backlog resolution pass (`CODE_REVIEW_BACKLOG.md` → "No open code defects remain": every code-defect item was fixed, built, tested and committed in passes 1-6). Re-open if this finding is still reproducible._


### Auto-fixed (1 issue, in files touched this session)
- `apps/ios/Todus/Todus/Features/Docs/DocEditorView.swift:scheduleDebouncedTitleSave` — debounced title save now snapshots `titleDraft` at schedule time and bails if the draft moved on while sleeping; previously a teardown-time `flushPendingSave` could race against the scheduled task reading a mutated draft.

### Needs human review (5 issues, in pre-existing files NOT touched this session)
- `apps/macos/TodusMac/Views/Docs/MacDocEditorPane.swift:167-168` (Critical) — `services.docsService.preAIEditSnapshot` and `wk` are force-unwrapped on AI revert. Crash if either nil. Fix: `guard let snap = …, let wk = …`.
- `apps/ios/Todus/Todus/Features/Docs/DocsWebView.swift:103-115,158-178` (Important) — WKNavigationDelegate callbacks dispatch via `Task { @MainActor in }` without weak self / cancellation token; stale reads possible if the WebView deallocs. Also no 401 retry: if the token rotates mid-load the page sticks.
- `apps/macos/TodusMac/Views/Docs/MacDocEditorPane.swift:93-97` (Important) — 5-minute `Task.sleep` revert timer not cancelled on `.onDisappear` — long-running background tasks accumulate.
- `apps/macos/TodusMac/Views/Docs/MacDocEditorPane.swift:156-160` (Important) — `flushPendingSave` swallows errors silently; if the doc was deleted while the editor was open, the user gets no signal. Log + surface.
- `apps/ios/Todus/Todus/Services/Docs/DocsService.swift:85-97` & `apps/macos/TodusMac/Services/Docs/MacDocsService.swift:128-139` (Minor) — Personal-workspace auto-create races + flag never resets across sign-out. Make idempotent server-side or via observable state.

---

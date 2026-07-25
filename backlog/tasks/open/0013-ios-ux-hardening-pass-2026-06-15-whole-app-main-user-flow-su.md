---
id: 0013
title: "iOS UX hardening pass — 2026-06-15 (whole-app, main user-flow surfaces)"
status: open
priority: P3
tags: [ios, ux, code-review-backlog]
files: []
created: 2026-06-15
source: CODE_REVIEW_BACKLOG.md
---

> Section overview — the individual findings from this section are separate items.

# iOS UX hardening pass — 2026-06-15 (whole-app, main user-flow surfaces)

Follow-up to the 2026-06-14 bug hunt: addressed the full finding set from three audits (UX flow assessment, UX-polish, bug-hunt) across the iOS app. 9 parallel implementer agents each owned a disjoint file set; every agent grep-verified symbols before use and deferred true feature-scope items. **Full `xcodebuild -scheme Todus` → BUILD SUCCEEDED** with all edits combined. 49 files changed (+1066/-224). Not yet committed with tests beyond the compile.

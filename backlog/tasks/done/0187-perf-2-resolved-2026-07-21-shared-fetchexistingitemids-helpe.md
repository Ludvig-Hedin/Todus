---
id: 0187
title: "PERF-2 — Resolved 2026-07-21 — shared fetchExistingItemIDs helper; all three pickers cache the set in @State p"
status: done
tags: [ios, performance, code-review-backlog]
files: [Features/Folders/AddToFolderSheet.swift]
created: 2026-07-11
source: CODE_REVIEW_BACKLOG.md
---

> Source context: iOS performance pass — deferred findings, 2026-07-11

| ID | File | Issue | Fix direction | Why deferred |
|----|------|-------|---------------|--------------|
| ~~PERF-2~~ | `Features/Folders/AddToFolderSheet.swift` | ~~Per-keystroke SwiftData `.fetch()` in the three `existing*IDs` computeds~~ | **Resolved 2026-07-21** — shared `fetchExistingItemIDs` helper; all three pickers cache the set in `@State` populated once in `.task` (membership can't change while the picker is up) | — |

---
id: 0069
title: "BH-0605-8 — onDisappear flush + an already-in-flight debounced saveTitleNow can issue two concurrent renameDoc"
status: open
priority: P4
tags: [ios, macos, bug-hunt, code-review-backlog]
files: []
created: 2026-06-05
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-05 — Bug hunt (iOS + macOS changed files) → Needs attention (not auto-fixed — TODO added in code where noted)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| BH-0605-8 | iOS docs | `DocEditorView.swift:~259` (`flushPendingSave`) | 🔵 low | `onDisappear` flush + an already-in-flight debounced `saveTitleNow` can issue two concurrent `renameDoc` for the same title (harmless if the server rename is idempotent). | Skip the flush write when an in-flight save targets the same `finalTitle`, or serialize through one save actor. |

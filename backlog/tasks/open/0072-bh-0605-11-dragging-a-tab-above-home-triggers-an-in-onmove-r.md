---
id: 0072
title: "BH-0605-11 — Dragging a tab above Home triggers an in-onMove re-pin that snaps it back below Home (confusing);"
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
| BH-0605-11 | iOS settings | `TabBarCustomizationView.swift:74` (`onMove`) | 🔵 low (UX) | Dragging a tab above Home triggers an in-`onMove` re-pin that snaps it back below Home (confusing); final saved order is still correct. | Add `.moveDisabled(tab.isRequired)` on the Home row so it can't leave index 0. |

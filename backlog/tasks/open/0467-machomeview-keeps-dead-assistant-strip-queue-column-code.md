---
id: 0467
title: "MacHomeView keeps dead assistant strip / queue column code"
status: open
priority: P4
tags: [macos, todo-sweep, dead-code]
files: [apps/macos/TodusMac/Views/Home/MacHomeView.swift]
created: 2026-07-25
source: code TODO/FIXME sweep
---

`MacHomeView.swift:578` and `:616` — `TODO(bug-hunt): Dead code` on `assistantPriorityStrip`, `assistantQueueColumn` and `macBriefingRowCard`; none are called.

## Fix shape

Delete them (and any types only they use). If they are a staging ground for a planned layout, move that plan to `docs/plans/open/` instead of parking it in the view file.

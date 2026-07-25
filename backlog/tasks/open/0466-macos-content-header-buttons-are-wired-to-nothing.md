---
id: 0466
title: "macOS content header buttons are wired to nothing"
status: open
priority: P2
tags: [macos, todo-sweep, ux]
files: [apps/macos/TodusMac/App/MacContentHeaderView.swift]
created: 2026-07-25
source: code TODO/FIXME sweep
---

Five `// TODO: wire to real actions` / `// TODO: wire to real search` markers at `MacContentHeaderView.swift:24,27,30,32,92`. The header renders controls that do nothing when clicked — a visible dead-affordance, not just tech debt.

## Fix shape

Either bind them to the existing services (global search already exists as `MacSearchView`) or remove the controls until they are backed.

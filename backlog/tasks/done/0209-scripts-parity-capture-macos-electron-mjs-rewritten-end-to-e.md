---
id: 0209
title: "scripts/parity/capture-macos-electron.mjs: rewritten end-to-end."
status: done
tags: [task-md, sprint]
files: [scripts/parity/capture-macos-electron.mjs]
created: 2026-05-24
source: TASK.md
---

> Source context: TASK.md → Task 16 — Design System screenshot regression suite (2026-05-24) — IN PROGRESS (infra DONE)

- `scripts/parity/capture-macos-electron.mjs`: rewritten end-to-end. The Electron wrapper was retired; the script now builds + launches `apps/macos/TodusMac` via `xcodebuild`, then captures the frontmost window via `screencapture -l <windowId>` (AppleScript resolves the window id). New `--surface`, `--interactive`, `--skip-build` flags. Filename kept for backwards-compat of the `pnpm parity:screenshots:capture:macos:auto` script entry; header docstring explains the rename.

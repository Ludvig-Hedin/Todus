---
id: 0205
title: "Extended parityscreenshots/manifest.json (v2): added 7 DesignSystem slugs with surface: \"design-syst"
status: done
tags: [task-md, sprint]
files: [parity_screenshots/manifest.json, check-screenshots.mjs]
created: 2026-05-24
source: TASK.md
---

> Source context: TASK.md → Task 16 — Design System screenshot regression suite (2026-05-24) — IN PROGRESS (infra DONE)

- Extended `parity_screenshots/manifest.json` (v2): added 7 DesignSystem* slugs with `surface: "design-system"` + `gated: true`. Added `macos` to the declared platforms so `check-screenshots.mjs` enforces macOS baselines for non-DS screens too (was previously silently uncovered).

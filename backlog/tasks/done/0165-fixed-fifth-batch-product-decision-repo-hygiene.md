---
id: 0165
title: "Fixed — fifth batch (product-decision + repo hygiene)"
status: done
tags: [code-review-backlog]
files: [package.json, pnpm-workspace.yaml]
created: 2026-06-13
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Backlog resolution pass — 2026-06-13 (whole-repo)

## Fixed — fifth batch (product-decision + repo hygiene)

- **B-033** (weekend snooze) — "weekend" now resolves to the nearest upcoming Sat OR Sun still in the future at 9am (Sat afternoon → Sun 9am). Shared helper on iOS + macOS; 5 new SnoozeOption tests.
- **B-036** (auto-resolve type) — an input with a date AND a specific time-of-day classifies as `.event` even without an event keyword ("Dentist Tuesday 2pm" → event); date-only stays `.task`. Added a `hasTime` flag through the parser models (iOS + macOS); 3 new parser tests.
- **B-035** (multi-intent date) — VERIFIED already-correct: `intent.date ?? selectedDate` is per-sub-intent (CompoundIntentParser parses each segment's own date). Contract documented in a comment.
- **B-001-root** (package-manager hygiene) — removed the redundant bun-only `workspaces`/`catalog` + top-level `patchedDependencies` from `package.json` (pnpm uses `pnpm-workspace.yaml`, which already holds the authoritative catalog/patches) and dropped the divergent `bun.lock`. pnpm is now the unambiguous single manager; pnpm resolution unchanged.

iOS now at **102 unit tests** (8 new), all green; iOS + macOS builds green.

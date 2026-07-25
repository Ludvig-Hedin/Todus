# Changelog

History — **what shipped**. Never tasks. A deferred item goes to
[`../backlog/`](../backlog/README.md); it never becomes a TODO inside a changelog entry.

## Layout

```
changelog/
  entries/unreleased/   committed, not yet tagged
  entries/released/     shipped under a version tag
  entries/archived/     legacy / unversioned history
```

Status is **section-driven, not date-driven**: whichever folder the file sits in is its
status. Untagged work is `unreleased` even if it shipped to production last week.

## Front matter

```yaml
---
id: 0325
title: "Short statement of what changed"
status: unreleased          # unreleased | released | archived
category: Fixed             # Added | Changed | Fixed | Security | Removed | Docs
release_date: 2026-07-25    # optional
version: v1.2.0             # optional, when tagged
tags: [ios, mail]           # optional
commits: [ee768b07]         # optional
files: []                   # optional
---
```

Bodies are prose explaining **what changed and why** — not a bullet dump of file names.

## Writing an entry

One entry file per meaningful item, written in the **same commit** as the change.

```bash
bun changelog:check                 # next free id + collisions
bun changelog:check --json
bun changelog:check --write-readme  # regenerate the unreleased table below
```

On release, `git mv` the entry from `entries/unreleased/` to `entries/released/`, set
`status: released`, and add `version` + `release_date`.

## Preserved prose

The root `CHANGELOG.md` was split into this folder on 2026-07-25. Everything in it moved
here verbatim. The only lines that did not become entries were its title
(`# Project Changelog`) and its `## [Unreleased]` section header — the folder now carries
that meaning. The root file is a pointer stub; the full original is in Git history.

Entry counts at migration: **20 unreleased**, **304 archived** (282 dated `##` sections
plus 22 loose one-line entries that had been appended below them), **0 released** — the
project has never tagged a version, so nothing qualified as `released`.

## Unreleased entries

<!-- agent-ops:index:start -->

| id | category | date | title |
| --- | --- | --- | --- |
| 0325 | Added | 2026-07-25 | [Added — agent operating system: backlog, user-tasks, changelog and agent memory](entries/unreleased/0325-added-agent-operating-system-backlog-user-tasks-changelog-agent-memory.md) |
| 0324 | Fixed | 2026-07-24 | [Fixed — native AI and task-save review follow-up](entries/unreleased/0324-fixed-native-ai-and-task-save-review-follow-up.md) |
| 0323 | Fixed | 2026-07-24 | [Changed — Bun workspace migration and release hardening](entries/unreleased/0323-changed-bun-workspace-migration-and-release-hardening.md) |
| 0322 | Added | 2026-07-23 | [Added — second-brain memory tools in native chat](entries/unreleased/0322-added-second-brain-memory-tools-in-native-chat.md) |
| 0321 | Fixed | 2026-07-23 | [Fixed — iOS AI chat sheet composer/layout](entries/unreleased/0321-fixed-ios-ai-chat-sheet-composer-layout.md) |
| 0320 | Fixed | 2026-07-22 | [Fixed — cross-platform performance and reliability pass](entries/unreleased/0320-fixed-cross-platform-performance-and-reliability-pass.md) |
| 0319 | Fixed | 2026-07-22 | [Fixed — iOS performance and reliability follow-up](entries/unreleased/0319-fixed-ios-performance-and-reliability-follow-up.md) |
| 0318 | Fixed | 2026-07-21 | [Fixed — iOS: UX-audit remediation wave (25 findings)](entries/unreleased/0318-fixed-ios-ux-audit-remediation-wave-25-findings.md) |
| 0317 | Added | 2026-07-17 | [Added — iOS Tasks: auto-organize, drag & drop, calmer rows](entries/unreleased/0317-added-ios-tasks-auto-organize-drag-drop-calmer-rows.md) |
| 0316 | Changed | 2026-07-11 | [Changed — iOS Tasks tab is less cramped](entries/unreleased/0316-changed-ios-tasks-tab-is-less-cramped.md) |
| 0315 | Fixed | 2026-07-11 | [Fixed — iOS performance & stability pass (lag / freezes / crashes)](entries/unreleased/0315-fixed-ios-performance-stability-pass-lag-freezes-crashes.md) |
| 0314 | Fixed | 2026-07-08 | [Fixed — iOS triple audit follow-up: deferred findings resolved](entries/unreleased/0314-fixed-ios-triple-audit-follow-up-deferred-findings-resolved.md) |
| 0313 | Fixed | 2026-07-08 | [Fixed — iOS audit verification wave](entries/unreleased/0313-fixed-ios-audit-verification-wave.md) |
| 0312 | Added | 2026-07-08 | [Added — iOS residual UX items shipped](entries/unreleased/0312-added-ios-residual-ux-items-shipped.md) |
| 0311 | Fixed | 2026-07-07 | [Fixed — iOS triple audit (UX assessment + UX polish + bug hunt)](entries/unreleased/0311-fixed-ios-triple-audit-ux-assessment-ux-polish-bug-hunt.md) |
| 0310 | Fixed | 2026-06-20 | [Fixed — legacy unreleased batch](entries/unreleased/0310-fixed-legacy-unreleased-batch.md) |
| 0309 | Added | 2026-06-13 | [Added — legacy unreleased batch](entries/unreleased/0309-added-legacy-unreleased-batch-2.md) |
| 0308 | Docs | — | [Docs — legacy unreleased batch](entries/unreleased/0308-docs-legacy-unreleased-batch.md) |
| 0307 | Changed | — | [Changed — legacy unreleased batch](entries/unreleased/0307-changed-legacy-unreleased-batch.md) |
| 0306 | Added | — | [Added — legacy unreleased batch](entries/unreleased/0306-added-legacy-unreleased-batch.md) |
| 0305 | Changed | — | [Accessibility / UX — legacy unreleased batch](entries/unreleased/0305-accessibility-ux-legacy-unreleased-batch.md) |

<!-- agent-ops:index:end -->

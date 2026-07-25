---
id: 0325
title: "Added — agent operating system: backlog, user-tasks, changelog and agent memory"
status: unreleased
category: Added
release_date: 2026-07-25
tags: [docs, tooling, agent-ops]
files: [backlog/, user-tasks/, changelog/, docs/agent-memory/, docs/plans/, scripts/agent-ops/, package.json]
---

### Added — agent operating system, 2026-07-25

Three monolithic Markdown files (`CHANGELOG.md` 4,678 lines, `CODE_REVIEW_BACKLOG.md`
1,192, `TASK.md` 737) were the only home for change history, review findings and sprint
work. Reading one item meant loading all of them, and two agents adding items meant two
conflicting edits to the same line range. Each is now a folder with one file per item and
a global `NNNN-<slug>.md` sequence, so an agent loads exactly the item it needs and two
sessions writing at once touch different files.

Four homes, never mixed: `backlog/` (code work an agent can pick up), `user-tasks/` (work
only the owner can do outside the codebase), `changelog/` (history, written in the same
commit as the change), `docs/agent-memory/` (durable gotchas, plus `active-work.md` for
file claims and `regressions.md` to grep before "fixing" something already fixed).

Everything migrated verbatim — 473 backlog items, 9 user tasks, 324 changelog entries —
with a line-level diff confirming nothing was dropped. The three root files are now
pointer stubs; their full contents remain in Git history.

Id allocation is no longer done by eye: `bun backlog:check`, `bun user-tasks:check` and
`bun changelog:check` print the next free id, regenerate the README index tables from
disk, and fail only on the collision that actually causes damage — the same id living in
two lifecycle folders, where an agent reads the stale copy and re-opens closed work.
`bun docs:check` reports doc-registration gaps, plan-lifecycle drift and broken links
without editing anything.

`CLAUDE.md` and `AGENTS.md` gained an identical **Team workflow** section covering branch
policy, file-claim etiquette, commit-with-changelog, follow-up routing, and the per-file
(never repo-wide) verification commands.

# Code review backlog

**Moved.** Review and bug-hunt findings now live in [`backlog/`](backlog/README.md), one
file per finding, split across `tasks/open/` and `tasks/done/`.

- Find work: the open-items table in [`backlog/README.md`](backlog/README.md), or
  `bun backlog:check --json`.
- File a finding: allocate an id with `bun backlog:check`, write
  `backlog/tasks/open/NNNN-<slug>.md`.
- Human-only actions (dashboards, signing, deploys) go to
  [`user-tasks/`](user-tasks/README.md) instead — never buried in a code backlog.

192 items were migrated verbatim on 2026-07-25. Two routing rules applied, both recorded
in `backlog/README.md`: findings from audits dated before this file's own 2026-06-13
resolution pass were migrated as `done` (each carries that quote and can be re-opened),
and sections that named themselves live were split one item per finding. The full
original remains in Git history.

# Plans

**Plans are intent.** Feature docs are reality, `backlog/` is remaining work, and Git is
history. Never conflate them, and never keep two canonical docs for one topic.

## Lifecycle

```
docs/plans/
  open/          approved, not started
  doing/         in flight
  done/YYYY/     shipped — filed by year
  archive/       abandoned or superseded
```

A plan moves through those folders; it is never edited into a status report. When a plan
lands, `git mv` it to `done/<year>/` and update the canonical feature doc — the plan does
not become the documentation.

Anything left over at the end of a plan goes to [`../../backlog/`](../../backlog/README.md)
(code) or [`../../user-tasks/`](../../user-tasks/README.md) (human action), not into the
plan file as a TODO.

**This is the only plans folder.** Do not create a second one.

## Pre-existing plan archive

`docs/superpowers/plans/` and `docs/superpowers/specs/` hold approved specs and
post-approval implementation plans from before this folder existed. They are accurate
(native SwiftUI era) and are left in place; treat them as `archive/` for anything dated
before 2026-07-25. Consolidating them into `done/` is a follow-up the repo owner has to
approve, since it rewrites paths other docs link to.

Loose plan-shaped files at the repo root (`plan.md`, `goal.md`, `PROJECT_PLAN.md`,
`PLANNING.md`, `ROADMAP.md`) predate this structure too. `PROJECT_PLAN.md`, `PLANNING.md`
and `ROADMAP.md` already carry "historical" banners pointing at the canonical docs.

## Status vocabulary

When a plan or doc describes functionality, mark it honestly — **Working · Partial ·
Static UI · Planned**. Never document planned functionality as implemented.

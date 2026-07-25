# Changelog

**Moved.** Change history now lives in [`changelog/`](changelog/README.md), one file per
entry, so agents can read a single entry instead of a 4,600-line file and two sessions can
add entries without colliding.

- New entries → `changelog/entries/unreleased/NNNN-<slug>.md`, written in the **same
  commit** as the change.
- Allocate the id with `bun changelog:check` — never by eye.
- Released entries move to `entries/released/`; the pre-migration history is in
  `entries/archived/`.

Everything that was in this file was migrated verbatim on 2026-07-25: **20** unreleased
entries and **304** archived entries. The full original remains in Git history.

# Changelog

The authoritative change log lives at **[`../changelog/`](../changelog/README.md)** — one
file per entry under `entries/{unreleased,released,archived}/`.

Write a new entry as `changelog/entries/unreleased/NNNN-<slug>.md` in the **same commit**
as the change; get the id from `bun changelog:check`. The root `../CHANGELOG.md` is now a
pointer stub — do not append to it.

This pointer exists only so the `docs/` reference set is complete; do **not** duplicate
change history here.

Related historical records:
- `docs/superpowers/plans/` and `docs/superpowers/specs/` — approved specs + post-approval implementation plans.
- `docs/PROJECT_UPDATES.md` — dated brand-rename + reorg snapshot (historical).

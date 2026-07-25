# Bun is the package manager — older docs and entries say pnpm

The workspace migrated from pnpm to **Bun 1.3.10** on 2026-07-24 (`packageManager:
"bun@1.3.10"`, `bun.lock` committed, CI/Docker/scripts updated). The Bun lockfile was
generated from the prior pnpm lock, so resolved versions carried over.

Anything written before that date — archived changelog entries, migrated backlog items,
`MANUAL_INPUTS_GUIDE.md` — still says `pnpm ...`. Read those as `bun ...`. Do not "fix"
historical entries; they are history.

The one thing to actually check: `bun run --filter=<pkg> <script>` is the working filter
form in this repo.

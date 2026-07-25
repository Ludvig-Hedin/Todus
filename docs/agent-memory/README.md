# Agent memory

Durable, shared facts for anyone — human or agent — working in this repo: gotchas,
surprising conventions, recurring debugging lessons, coordination rules, non-obvious
operational facts.

## Authority boundary

**Canonical docs and the code outrank this folder.** If a note here disagrees with
`AGENT_CONTEXT.md`, `PRD.md`, the `docs/` reference set, or the source, they win and the
note is wrong — fix it.

This folder is **not** for product scope, feature status, routes, roadmap, session logs,
or chain-of-thought. Those live in the canonical docs, `backlog/`, and `changelog/`.

Precedence, highest first:

1. Owner directive
2. Product source of truth (`PRD.md`)
3. Code and tests
4. Canonical feature docs (`AGENT_CONTEXT.md`, `FEATURES.md`, `docs/`)
5. Plans (`docs/plans/`)
6. Audits (`docs/audits/`)
7. This folder

## Index

| File | What it holds |
|------|---------------|
| [active-work.md](active-work.md) | Who is touching which files right now — read at session start |
| [regressions.md](regressions.md) | Every fixed bug: symptom / cause / fix / test / keywords. **Grep before "fixing".** |
| [frontend-app-and-deploy-scripts.md](frontend-app-and-deploy-scripts.md) | `apps/web` is the app; `apps/mail` is read-only; root deploy scripts still target the archive |
| [trpc-mount-keys.md](trpc-mount-keys.md) | Client router keys that differ from their file names |
| [native-http-calls.md](native-http-calls.md) | Why native API calls use `URLSession`, never `WKWebView` fetch |
| [package-manager.md](package-manager.md) | Bun is the package manager; docs and older entries still say pnpm |
| [verification-etiquette.md](verification-etiquette.md) | Never run repo-wide lint/format; one owner per heavy gate |
| [agent-ops-ids.md](agent-ops-ids.md) | Never allocate a backlog / user-task / changelog id by eye |

## Adding a note

One focused fact per file. Short. If it stops being true, delete it — a stale memory is
worse than no memory.

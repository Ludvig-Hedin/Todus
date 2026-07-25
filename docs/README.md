# Todus — Technical Reference (`docs/`)

> **The canonical agent landing doc is [`../AGENT_CONTEXT.md`](../AGENT_CONTEXT.md)** — read that first for the repo map, feature index, and working rules. This `docs/` set is the code-derived technical reference: deeper, per-subsystem detail kept in sync with `apps/server` and `apps/web`.
>
> Last verified against source: **2026-06-13**.

## Reference set

| Doc | Covers |
|-----|--------|
| [architecture.md](architecture.md) | System overview, the five apps, shared data model, request lifecycle, integrations |
| [backend.md](backend.md) | `apps/server` — Hono, tRPC, Durable Objects, Workflows, Queues, KV, R2, Vectorize, bindings, env |
| [frontend.md](frontend.md) | `apps/web` — React Router v7, routing, state, styling, build/deploy (`ssr: false` + prerender) |
| [database.md](database.md) | PostgreSQL schema (Drizzle), every table, migration flow |
| [api.md](api.md) | tRPC router catalog + **client mount keys** (which differ from file names) + REST/webhook/MCP HTTP routes |
| [deployment.md](deployment.md) | Cloudflare deploy (web + backend), DB migrations, macOS DMG→R2, iOS/TestFlight, CI/CD |
| [mcp.md](mcp.md) | The MCP server the app **provides** (ZeroMCP / ThinkingMCP) + how to connect |
| [agents.md](agents.md) | How AI coding agents should work in this repo — rules, gotchas, verification |
| [changelog.md](changelog.md) | Pointer to the canonical [`../changelog/`](../changelog/README.md) entry folder |

## Governed folders

Added 2026-07-25. **Any new doc must be registered in this file.**

| Folder | Holds |
|--------|-------|
| [agent-memory/](agent-memory/README.md) | Durable repo gotchas, `active-work.md` file claims, `regressions.md`. Outranked by the canonical docs and the code. |
| [plans/](plans/README.md) | Plans, moving `open/ → doing/ → done/<year>/ → archive/`. The only plans folder — do not create a second one. |
| [`../backlog/`](../backlog/README.md) | Code / agent follow-ups, one file per item |
| [`../user-tasks/`](../user-tasks/README.md) | Work only the repo owner can do, outside the codebase |
| [`../changelog/`](../changelog/README.md) | Shipped history, one file per entry |

Structural validator: `bun docs:check` (report-only — registration gaps, plan-lifecycle
drift, broken relative links, empty lifecycle folders).

## Other registered docs

| Doc | Covers |
|-----|--------|
| [ios-followup-tasks.md](ios-followup-tasks.md) | Agent-ready specs for the iOS follow-up work from the 2026-07-07/08 triple audit |
| [testflight-checklist.md](testflight-checklist.md) | TestFlight submission checklist |
| [agent-ops-system-setup-prompt.md](agent-ops-system-setup-prompt.md) | The portable prompt that created `backlog/`, `user-tasks/`, `changelog/`, `docs/agent-memory/` and the governance rules |
| [audits/](audits/) | Dated audit evidence (performance, UX). Historical once resolved. |
| [voice/](voice/) | Voice assistant phase docs |

## Native apps

iOS and macOS are **native SwiftUI** (Swift 6, iOS 18+ / macOS 15+). See [`../AGENT_CONTEXT.md`](../AGENT_CONTEXT.md) §4 and [`../CLAUDE.md`](../CLAUDE.md) for their folder structure. There is **no** React Native / Expo / Electron client — any doc that says otherwise is historical.

## Legacy subfolders in this directory

The dated subfolders below predate the native-SwiftUI + `apps/web` rewrite and are **stale / superseded** by the files above and the root canonical docs. Treat as historical only:

- `architecture/`, `deployment/`, `development/`, `guides/` — describe the old Expo / Electron / Next.js / `apps/mail` stack; several files are byte-identical stale duplicates of root docs (`APPS_STRUCTURE.md`, `TESTFLIGHT_QUICK_START.md`) or divergent stale forks (`guides/AGENTS.md`, `architecture/APPS_ARCHITECTURE.md`).
- `superpowers/` — the **healthy** historical archive (approved specs + post-approval plans, all correctly native SwiftUI). Keep.
- `voice/PHASE_1.md` — accurate except a stale `xcodegen generate` step (macOS no longer uses xcodegen; its `.xcodeproj` is checked in).
- Loose files (`MIGRATION_GUIDE.md`, `share-asap.md`, `terminal-commands.md`, `PROJECT_UPDATES.md`, `local-duplicate-audit.md`, `sender-avatar-resolution.md`) — historical / niche.

The full authoritative doc map (active vs historical) lives in [`../AGENT_CONTEXT.md`](../AGENT_CONTEXT.md) §10.

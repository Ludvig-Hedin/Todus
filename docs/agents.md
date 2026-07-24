# Agents

> How AI coding agents should operate in this repo. The **canonical, fuller version is [`../AGENT_CONTEXT.md`](../AGENT_CONTEXT.md)** (and its mirrors [`../CLAUDE.md`](../CLAUDE.md), [`../AGENTS.md`](../AGENTS.md), [`../GEMINI.md`](../GEMINI.md)). This page is the quick rule card + the gotchas that bite newcomers. Last verified: 2026-06-13.

## Hard rules

1. **Never edit `apps/mail/`** — it's the read-only legacy archive (`@zero/mail`). All frontend work goes in `apps/web/` (`@zero/web`).
2. **Never edit `apps/archived/`** — reference only.
3. **No project-wide lint/format.** `bun check` / `bun lint` / `bun format` sweep the whole monorepo. Only lint/format files you touched (`npx eslint <file>`, `npx prettier --write <file>`).
4. **No new git branches** unless asked; commit on the existing branch. Only commit files you intentionally changed — never bundle unrelated working-tree changes.
5. **Verify, don't assume.** If unsure a path/symbol exists, read it. Code is the source of truth; if a doc disagrees, the code wins (and fix the doc).
6. **Update docs when behavior/architecture changes** — `CHANGELOG.md` plus the relevant reference (`PRD.md` / `TASK.md` / `APPS_ARCHITECTURE.md` / this `docs/` set).
7. **Design tokens change in all three platforms together** — `apps/web/app/globals.css` + `apps/ios/.../AppTheme.swift` + `apps/macos/.../MacTheme.swift` + [`../DESIGN_SYSTEM.md`](../DESIGN_SYSTEM.md). Canonical dark bg `#1c1c1e`. Contrast bugs are functional bugs.

## Gotchas that waste time

- **Deploy the active app with `bun run --filter=@zero/web build|deploy`.** Root `build:frontend`/`deploy:frontend` still ship the legacy `@zero/mail`.
- **Web is `ssr: false`** (client-rendered SPA) with build-time prerender of marketing pages — not per-request SSR. See [frontend.md](frontend.md).
- **tRPC client mount keys ≠ file names** for `cookies`→`cookiePreferences`, `label`→`labels`, `mail-assistant`→`mailAssistant`, and `tasks.ts` also exports `folders`. See [api.md](api.md).
- **Native API calls use `URLSession` + Bearer**, never `WKWebView` fetch (`loadHTMLString` gives a `null` origin → CORS failures). iOS/macOS `Services/` folders deliberately mirror each other — port logic across both.
- **iOS still uses xcodegen; macOS does not** — the macOS `.xcodeproj` is checked in (no `project.yml`). Ignore docs that say `xcodegen generate` for macOS.
- **`bun dev` runs `apps/web` on `:3000`** and proxies `/api`,`/sse`,`/agents` to the backend on `:8787`.

## What runs where (for orientation)

- The MCP server the **app** exposes (ZeroMCP/ThinkingMCP) is documented in [mcp.md](mcp.md) — not to be confused with a coding agent's own dev-tooling MCP.
- Backend subsystems (DOs, Workflows, Queues, env): [backend.md](backend.md). DB: [database.md](database.md). Deploy/CI: [deployment.md](deployment.md).

When in doubt, ask. Don't guess.

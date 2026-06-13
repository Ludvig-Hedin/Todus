# MCP

> The MCP (Model Context Protocol) servers the Todus **backend exposes to users / external AI clients**. This is distinct from any dev-tooling MCP a coding agent has in its own session. Derived from `apps/server/src/main.ts`, `src/routes/agent/mcp.ts`, `src/lib/sequential-thinking.ts`, and [`../MCP.md`](../MCP.md). Last verified: 2026-06-13.

## Servers the app provides

| Server | Class / binding | HTTP mount | Auth |
|---|---|---|---|
| **Todus MCP** | `ZeroMCP` (`McpServer{name: 'zero-mcp'}`) / `ZERO_MCP` | `/sse` (SSE), `/mcp` (streamable) | Better Auth session — `auth.api.getMcpSession(headers)`, **401 without** |
| **Thinking MCP** | `ThinkingMCP` / `THINKING_MCP` | `/mcp/thinking/sse` | **None** (open SSE) — internal sequential-thinking reasoning aid |

`ZeroMCP` is the user-facing one: it registers tools backed by the signed-in user's email connections (resolved through Hyperdrive/Drizzle), e.g. `getConnections`, `getThreadSummary`, and the capabilities below.

## Capabilities (Todus MCP)

**Email:** get thread by ID, list emails in a folder, create + send email, create draft, send existing draft, delete, mark read/unread, modify labels, bulk archive, bulk delete.
**Labels:** list user labels, create custom labels (with colors), delete labels.
**AI:** compose email with AI, ask about mailbox, ask about a specific thread, web search (Perplexity).
**Search/organize:** search with custom queries, filter by label, archive/trash management.

## Connecting

Two methods (per [`../MCP.md`](../MCP.md)):

1. **Better Auth session token** — copy the session cookie from the Todus web app into the `Authorization` header; either the full cookie field, or the form `better-auth-{env}.session_token={value}` (`env` = `dev` locally).
2. **OAuth** — coming soon.

Endpoints: `https://api.todus.app/sse` or `https://api.todus.app/mcp` (local: the dev backend on `:8787`).

## Notes

- There is **no repo-level `.mcp.json`** — the repo ships no checked-in dev MCP config.
- `/mcp/thinking/sse` (ThinkingMCP) has no auth check by design — it exposes a generic thought/branch/revision processor, not user data.
- The `mcp` Better Auth plugin (`src/lib/auth.ts`) backs the session resolution used by `ZeroMCP`.

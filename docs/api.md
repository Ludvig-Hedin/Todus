# API

> tRPC + HTTP surface of `apps/server`. Derived from `src/trpc/index.ts` and `src/main.ts`. Last verified: 2026-07-23.

## How clients call it

- **Web:** tRPC client via `@trpc/tanstack-react-query` (`apps/web`).
- **Native (iOS/macOS):** `POST /api/trpc/<mountKey>` with a Superjson-wrapped body and `Authorization: Bearer <token>` (token in Keychain). Client: `TodosAPIClient` (iOS) / `MacTodosAPIClient` (macOS).

## tRPC routers — **client mount keys** (source of truth: `src/trpc/index.ts`)

These are the keys you call on the client (`trpc.<key>...`). 29 routers:

`assistant`, `ai`, `avatar`, `bimi`, `brain`, `calendar`, `categories`, `connections`, `cookiePreferences`, `drafts`, `groups`, `labels`, `mailAssistant`, `mail`, `mentions`, `notes`, `shortcut`, `sessions`, `settings`, `sharing`, `user`, `templates`, `meet`, `logging`, `tasks`, `folders`, `docs`, `subscription`, `contact`

### ⚠️ Mount key ≠ file name

Most routers mount under their file name, but four do not — calling the file name will fail:

| Router file (`src/trpc/routes/`) | Client mount key |
|---|---|
| `cookies.ts` (`cookiePreferencesRouter`) | **`cookiePreferences`** |
| `label.ts` (`labelsRouter`) | **`labels`** |
| `mail-assistant.ts` (`mailAssistantRouter`) | **`mailAssistant`** |
| `tasks.ts` (`tasksRouter` + `foldersRouter`) | **`tasks`** *and* **`folders`** (one file, two mounts) |

All other files map 1:1 (`mail.ts`→`mail`, `docs.ts`→`docs`, …). `groups-cursor.ts` is a helper for `groups`, not a separate mount.

### Router purpose (one-liner each)

| Mount key | Purpose |
|---|---|
| `mail` | Threads, messages, archive/read/send actions |
| `mailAssistant` | Compose/reply AI help |
| `ai` | AI chat / SSE streaming, model selection |
| `assistant` | Briefing / open-loop assistant, person & workstream memory, feedback, snapshots |
| `brain` | Background email-intelligence enable/disable + state |
| `connections` | Connected mailbox accounts (list/add/delete) |
| `labels` | Gmail label management |
| `categories` | Email category management |
| `drafts` | Email draft CRUD |
| `templates` | Email templates CRUD |
| `notes` | Per-thread notes |
| `mentions` | @-mention resolution |
| `avatar` / `bimi` | Sender avatars / BIMI brand logos |
| `calendar` | Calendar events CRUD (Google) |
| `tasks` / `folders` | Tasks + task folders / folder items |
| `docs` | Docs/workspaces (Tiptap), tree |
| `meet` | Meetings (Recall.ai bot, transcripts, media) |
| `groups` | Group chat/messaging (cursor pagination) |
| `sharing` | Shared AI conversations / share links |
| `subscription` | Billing/subscription (Autumn) state |
| `settings` / `shortcut` / `cookiePreferences` | User settings / hotkeys / cookie consent |
| `sessions` | Active session list/revoke |
| `user` / `contact` / `logging` | Profile / contact form / client log ingestion |

When adding a domain: create `src/trpc/routes/<name>.ts`, register it in `src/trpc/index.ts`, then call it from the client.

Native task reconciliation uses `tasks.sync` for mutation batches, paginated `tasks.list` for live rows,
and paginated `tasks.deleted` for explicit cross-device deletion evidence. Tombstones are durable and
deletion wins over stale native upserts; clients must never infer deletion from absence in an offset page.

## Non-tRPC HTTP routes (`src/main.ts`)

| Route | Purpose | Auth |
|---|---|---|
| `/api/auth/*` | Better Auth (sign-in/up, OTP, social, sessions) | per-endpoint |
| `/api/auth/mobile-token` | Native session handoff (dedicated `session` row + JWT/refresh) | OAuth callback |
| `/sse`, `/mcp` | `ZeroMCP` user-facing MCP server | Better Auth session (401 without) |
| `/mcp/thinking/sse` | `ThinkingMCP` sequential-thinking MCP | **none** (open SSE) |
| `/webhooks/recall` | Recall.ai meeting webhooks | webhook secret |
| `/webhooks/autumn` | Autumn billing webhooks | webhook secret |
| `/a8n/notify/:providerId` | Google Pub/Sub push (inbound mail) | provider verification |
| `/health` | Health check | none |
| `/admin/run-migrations` | Run DB migrations | `ADMIN_RUN_MIGRATIONS_TOKEN` |
| `/monitoring/sentry` | Sentry tunnel | — |

See [mcp.md](mcp.md) for the MCP capability catalog and connection methods, and [backend.md](backend.md) for bindings/env.

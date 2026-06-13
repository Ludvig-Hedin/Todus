# Backend (`apps/server`)

> Code-derived from `apps/server/src/main.ts`, `wrangler.jsonc`, `src/env.ts`, `src/lib/auth.ts`. Last verified: 2026-06-13. API surface: [api.md](api.md). DB: [database.md](database.md).

## Runtime

- **Platform:** Cloudflare Worker (`name: todus-server-v1`, `main: src/main.ts`, `compatibility_date 2025-05-01`).
- **HTTP framework:** Hono. Entry point `src/main.ts` mounts every route.
- **API layer:** tRPC v11 + Superjson. Router composed in `src/trpc/index.ts` from per-domain files in `src/trpc/routes/`. Full catalog: [api.md](api.md).
- **Database:** PostgreSQL via Drizzle ORM behind Cloudflare **Hyperdrive** (`HYPERDRIVE` binding). Schema `src/db/schema.ts`; Zod validators `src/lib/schemas.ts`.
- **Environments:** `local`, `staging`, `production` (three `env` blocks in `wrangler.jsonc`). Prod API `api.todus.app`, staging `sapi.todus.app` — custom domains are attached in the Cloudflare dashboard (no `routes` key in wrangler).

## Durable Objects (8)

| Class | Binding | Purpose |
|---|---|---|
| `ZeroDriver` | `ZERO_DRIVER` | Per-connection mail driver/state |
| `ZeroAgent` | `ZERO_AGENT` | Agent runtime |
| `ZeroDB` | `ZERO_DB` | DB-backed durable state |
| `ZeroMCP` | `ZERO_MCP` | **User-facing MCP server** (email/label/AI tools) — see [mcp.md](mcp.md) |
| `ThinkingMCP` | `THINKING_MCP` | Sequential-thinking MCP (reasoning aid) |
| `ShardRegistry` | `SHARD_REGISTRY` | Connection sharding registry |
| `WorkflowRunner` | `WORKFLOW_RUNNER` | Workflow execution coordination |
| `ThreadSyncWorker` | `THREAD_SYNC_WORKER` | Per-connection thread sync worker |

## Cloudflare Workflows (2)

- `SyncThreadsWorkflow` (`SYNC_THREADS_WORKFLOW`)
- `SyncThreadsCoordinatorWorkflow` (`SYNC_THREADS_COORDINATOR_WORKFLOW`)

Both fan out async Gmail thread sync. Toggle via `DISABLE_WORKFLOWS`.

## Other bindings

- **Hyperdrive:** `HYPERDRIVE` (Postgres; local `:5433/todus`).
- **AI:** `AI` (Workers AI).
- **Vectorize:** `VECTORIZE` (threads), `VECTORIZE_MESSAGE` (messages).
- **R2:** `THREADS_BUCKET` (`threads` / `threads-staging`). (Releases bucket `todus-releases` is used by the macOS DMG script.)
- **Queues:** producers + consumers for `thread_queue`, `subscribe_queue`, `send_email_queue` (env-suffixed `-prod` / `-staging`).
- **KV (10):** `gmail_history_id`, `gmail_processing_threads`, `subscribed_accounts`, `connection_labels`, `prompts_storage`, `gmail_sub_age`, `pending_emails_status`, `pending_emails_payload`, `scheduled_emails`, `snoozed_emails`.
- **Cron:** `0 0 * * *` + `0 * * * *` (staging + production only) → `scheduled()` runs `processScheduledEmails` + `processExpiredSubscriptions`.

## HTTP routes (non-`/api/trpc`)

- `/api/auth/*` — Better Auth (incl. `/api/auth/mobile-token` native session handoff).
- MCP: `/sse` + `/mcp` → `ZeroMCP` (auth-gated); `/mcp/thinking/sse` → `ThinkingMCP` (open). See [mcp.md](mcp.md).
- Webhooks: `/webhooks/recall` (Recall.ai), `/webhooks/autumn` (billing).
- `/a8n/notify/:providerId` — Google Pub/Sub push for inbound mail.
- `/health`, `/admin/run-migrations` (token-gated), `/monitoring/sentry` (tunnel).

## Auth (Better Auth — `src/lib/auth.ts`, `src/lib/auth-providers.ts`)

- **Plugins enabled:** `mcp`, `jwt` (15-min access token), `bearer`, `phoneNumber` (Twilio OTP), `emailOTP` (Resend, 6-digit, 5-min). `dubAnalytics` only if `DUB_API_KEY` set.
- **Email/password:** enabled with `requireEmailVerification: true`, `sendOnSignUp: true`.
- **Social:** **Google** (required; full Gmail + contacts + calendar scopes), **Apple** (native multi-bundle-ID verifier for `com.ludvighedin.todus` + `com.ludvighedin.todus.macos`; web via Services ID).
- **Account linking:** enabled (`trustedProviders: google, microsoft, apple`).
- **Commented out / disabled:** **Microsoft** provider, the legacy "Zero" `customProviders`, and OTel instrumentation.
- `trustedOrigins` are hardcoded in `createAuthConfig()` — **update when adding an origin**. `COOKIE_DOMAIN=todus.app` in production.
- See [`../AGENT_CONTEXT.md`](../AGENT_CONTEXT.md) §6 for the native bearer/refresh flow.

## Environment

Typed in `src/env.ts`; non-secret values in `wrangler.jsonc` `vars`; secrets via `wrangler secret` / dashboard.

**Public `vars`:** `NODE_ENV`, `COOKIE_DOMAIN`, `VITE_PUBLIC_BACKEND_URL`, `VITE_PUBLIC_APP_URL`, `BETTER_AUTH_URL`, `DISABLE_CALLS`, `DROP_AGENT_TABLES`, `THREAD_SYNC_MAX_COUNT`, `THREAD_SYNC_LOOP`, `DISABLE_WORKFLOWS`, `OTEL_*`, `DD_API_KEY`, `DD_APP_KEY`, `DD_SITE`.

**Secret names** (NAMES only — never commit values): `BETTER_AUTH_SECRET`, `DATABASE_URL`, `GOOGLE_CLIENT_ID/SECRET/REDIRECT_URI`, `GOOGLE_APPLICATION_CREDENTIALS`, `GOOGLE_GENERATIVE_AI_API_KEY`, `APPLE_CLIENT_ID/TEAM_ID/KEY_ID/PRIVATE_KEY`, `RESEND_API_KEY`, `REDIS_URL/TOKEN`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `OPENROUTER_API_KEY/SECRET`, `GROQ_API_KEY`, `PERPLEXITY_API_KEY`, `TAVILY_API_KEY`, `TWILIO_ACCOUNT_SID/AUTH_TOKEN/PHONE_NUMBER`, `AUTUMN_SECRET_KEY/WEBHOOK_SECRET`, `DUB_API_KEY`, `MEM0_API_KEY`, `RECALL_API_KEY/BASE_URL/WEBHOOK_SECRET`, `COMPOSIO_API_KEY`, `ARCADE_API_KEY`, `VOICE_SECRET`, `ELEVENLABS_API_KEY`, `MICROSOFT_CLIENT_ID/SECRET` (provider disabled), `GITHUB_CLIENT_ID/SECRET`, `ADMIN_RUN_MIGRATIONS_TOKEN`, plus model/prompt config (`DEFAULT_MODEL`, `FAST_MODEL_*`, `AI_SYSTEM_PROMPT`) and analytics keys (`VITE_PUBLIC_POSTHOG_*`, `AXIOM_*`). The full set is enumerated in `src/env.ts`.

## Deploy

`pnpm deploy:backend` → `wrangler deploy --env production` (staging via the `deploy:staging` script in `apps/server`). DB migrations: see [deployment.md](deployment.md).

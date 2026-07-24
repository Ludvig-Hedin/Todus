# Database

> PostgreSQL via Drizzle ORM behind Cloudflare Hyperdrive. Schema: `apps/server/src/db/schema.ts` (table prefix `mail0_` via `createTable`). Zod validators: `apps/server/src/lib/schemas.ts`. Last verified: 2026-06-13.

## Connection

- Production/staging: Postgres origin reached through the `HYPERDRIVE` binding in `apps/server/wrangler.jsonc`. Direct origin URL (for migrations) is `DATABASE_URL` / `PRODUCTION_DATABASE_URL`.
- Local dev: Docker Postgres 17 on `:5433`, database `todus` (`docker-compose.db.yaml`, started by `bun docker:db:up` / `bun go`).

## Tables (38)

Grouped by domain. Names below are the logical Drizzle table names.

**Identity & auth**
`user`, `session`, `sessionMetadata`, `account`, `verification`, `userHotkeys`, `jwks`, `oauthApplication`, `oauthAccessToken`, `oauthConsent`, `earlyAccess`

**Mail & connections**
`connection`, `summary`, `note`, `userSettings`, `writingStyleMatrix`, `emailTemplate`, `marketingEmailDelivery`

**AI assistant / briefing**
`assistantOpenLoop`, `assistantPreparedAction`, `assistantPersonMemory`, `assistantWorkstreamMemory`, `assistantFeedback`, `assistantBriefingSnapshot`, `aiConversation`, `sharedConversation`

**Tasks**
`task`, `taskFolder`, `folderItem`

**Docs**
`docWorkspace`, `doc`

**Meetings**
`meetIntegration`, `meeting`, `meetingMedia`, `meetingTranscript`

**Groups / messaging**
`group`, `groupMember`, `groupMessage`

**Integrations**
`slackConnection`

## Key tables (columns that matter)

| Table | Key columns | Notes |
|---|---|---|
| `user` | `id` (PK), `email`, `emailVerified`, `name` (NOT NULL), `image`, `plan`, `subscription_status`, `ai_usage_used`, `ai_usage_limit`, `ai_usage_reset_at` | Billing/usage fields are cached on the user row |
| `session` | `id` (PK), `token` (raw native session token), `userId`, `expiresAt` (90-day sliding), `ipAddress`, `userAgent` | Native bearer/refresh flow; `/api/auth/mobile-token` inserts a dedicated row per native client |
| `account` | `providerId`, `accessToken`, `refreshToken`, `idToken`, `accessTokenExpiresAt`, `userId` | Better Auth OAuth identity |
| `connection` | `id` (PK), `providerId`, `email`, `accessToken`, `refreshToken`, `scope`, `expiresAt`, `userId`; unique (`email`,`userId`) | Connected mailbox — drives all mail API access |
| `userSettings` | `id` (PK), `userId` (unique), `settings` (jsonb) | jsonb shape validated by `userSettingsSchema` |
| `doc` | `workspaceId`, `parentId`, `content` (jsonb), `linkedThreadId/EventId/TaskId`, `isStarred` | Tiptap docs; nestable via `parentId` |
| `task` / `taskFolder` / `folderItem` | task records + folders + folder membership | Mirrors the SwiftData `TaskRecord`/`FolderRecord` on native |

## Migration workflow (Drizzle)

```bash
bun db:generate    # generate a migration from schema.ts changes
# → review the generated SQL in apps/server/src/db/migrations/
bun db:migrate     # apply migrations
bun db:push        # push schema directly (dev only)
bun db:studio      # Drizzle Studio GUI
```

Order is always **generate → review → migrate/push**. Production migrations run via the `db-migrate-production.yml` GitHub Action (push to `main` touching `apps/server/src/db/migrations/**` or `drizzle.config.ts`, or manual dispatch) against `PRODUCTION_DATABASE_URL`. See [deployment.md](deployment.md).

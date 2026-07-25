# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **New here? Read [AGENT_CONTEXT.md](AGENT_CONTEXT.md) first.** It's the canonical agent reference — repo layout, feature map, where every doc lives, recent work. This file is the Claude-specific delta on top of that.

## Monorepo Structure

This is a **bun + Turborepo** monorepo. The active apps are:

| App | Path | Stack | Purpose |
|-----|------|-------|---------|
| Frontend (active) | `apps/web` | React Router v7 + Vite + Cloudflare Workers | Marketing + mail product + settings — the whole user-facing surface |
| ~~Frontend (legacy)~~ | `apps/mail` | React Router v7 + Vite + Cloudflare Workers | **READ-ONLY. Do not edit.** Superseded by `apps/web`. |
| Backend | `apps/server` | Cloudflare Worker (Hono + tRPC + Durable Objects + Workflows) | Auth, mail APIs, AI workflows, Postgres via Hyperdrive |
| iOS | `apps/ios/Todus` | Native SwiftUI (Xcode, Swift 6, iOS 18+) | iPhone app |
| macOS | `apps/macos/TodusMac` | Native SwiftUI (Xcode, Swift 6, macOS 15+) | Desktop app (DMG via Cloudflare R2) |

**Do not use** anything under `apps/archived/` — those are reference-only legacy implementations.

> **IMPORTANT — `apps/mail/` is READ-ONLY.**
> All frontend work now lives in `apps/web/`. Never edit any file under `apps/mail/`. Treat it as an archived reference. If you need to make a frontend change, make it in `apps/web/` instead.
>
> ⚠️ `bun build:frontend` and `bun deploy:frontend` in root `package.json` still target `@zero/mail` (the legacy archive). To actually ship `apps/web`, run `bun run --filter=@zero/web build` and `bun run --filter=@zero/web deploy` directly until those scripts are fixed.

## Design System

Cross-platform design tokens are documented and tracked. **Update these when you change colors, typography, radius, spacing, or motion.**

- **Canonical reference:** [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) — tokens, accent palette, component cross-reference, "how to change"
- **Known gaps:** [DESIGN_SYSTEM_INCONSISTENCIES.md](DESIGN_SYSTEM_INCONSISTENCIES.md) — drift, resolved + open
- **Live viewers** (gated to `TODUS_ALLOWLISTED_EMAILS` / `VITE_TODUS_ALLOWLISTED_EMAILS` allowlist):
  - Web: `/settings/design-system`
  - iOS: Settings → Developer → Design System
  - macOS: Settings → Developer → Design System
- **Sources of truth:**
  - Web: `apps/web/app/globals.css`
  - iOS: `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift`
  - macOS: `apps/macos/TodusMac/DesignSystem/MacTheme.swift`
- **Allowlist mechanism:** `packages/swift-auth/Sources/TodusAuth/TodusDeveloperAccess.swift` (Swift), `apps/web/lib/developer-access.ts` (web)
- **Motion tokens:** `Motion.fast / base / slow` per platform — prefer these over inline `.snappy(...)`, `.easeOut(...)`, `duration-150`, etc.
- **Dark background canonical:** Apple system dark `#1c1c1e` (`Color(white: 0.109)` on iOS / macOS)

## Key Commands

```bash
# Development
bun go                         # Start Docker DB + apps/web + backend (full local stack)
bun dev                        # Start apps/web + backend (DB must already be running)
bun web                        # Alias for bun dev
bun mail                       # Start apps/mail (mail product) only
bun docker:db:up               # Start PostgreSQL in Docker
bun docker:db:stop             # Stop PostgreSQL
bun docker:db:down             # Remove PostgreSQL container
bun docker:db:clean            # Remove PostgreSQL container and volumes
bun ios                        # Start the iOS app
bun ios:simulator              # Launch the iOS simulator flow
bun ios:build:preview          # Build iOS preview artifact
bun ios:build:production       # Build iOS production artifact
bun macos                      # Start the macOS app
bun android                    # Start the Android app
bun scripts                    # Run repo scripts via tsx

# Database
bun db:generate                # Generate migration from schema changes
bun db:migrate                 # Apply migrations
bun db:push                    # Push schema changes directly
bun db:studio                  # Drizzle Studio GUI

# Build & Deploy
bun run build                      # Build all packages
bun build:frontend             # Build apps/mail (the deployed mail product)
bun deploy:frontend            # Deploy apps/mail to Cloudflare
bun deploy:backend             # Deploy backend to Cloudflare Workers
bun sentry:sourcemaps          # Upload frontend source maps

# Evaluations and parity
bun test:ai                    # Run backend AI tests
bun eval                       # Run backend evals
bun eval:dev                   # Run backend evals in dev mode
bun eval:ci                    # Run backend evals in CI mode
bun parity:screenshots:check   # Compare screenshot parity
bun parity:screenshots:sync    # Sync screenshot logs
bun parity:screenshots:capture:ios
bun parity:screenshots:capture:ios:auto
bun parity:screenshots:capture:android:auto
bun parity:screenshots:capture:macos:auto

# Quality
bun precommit                 # Run oxlint --deny-warnings on staged files
bun lint                      # ESLint (turbo)
bun format                    # Prettier write for app code
bun check                     # Format check + lint
bun check:format              # Prettier check
bun run test                      # Run tests (packages/testing)
bun test:watch                # Watch tests
bun test:coverage             # Coverage run
bun test:ui                   # UI test runner
bun run test -- -t "test name"     # Single test
```

### Important Restrictions
- **NEVER run project-wide lint/format commands** (`bun check`, `bun lint`, `bun format`) — these touch the entire codebase. Only lint/format specific files you changed.

### Current Workflow Notes
- `bun dev` / `bun web` starts `apps/web` (marketing + mail + settings — the full frontend) + the backend.
- `bun mail` starts the **legacy** `apps/mail` archive — only use if you need to compare against the old code. Never edit it.
- Prefer `bun go` when you need the full local stack; it brings up Docker Postgres before the app processes.
- Use `bun ios:simulator` for simulator debugging, but `bun ios` is the lighter app-start command.
- Use `bun macos` for the native macOS app; the old Electron flow is obsolete.
- When adding schema changes, keep the order `db:generate` → review migration → `db:migrate` or `db:push` as appropriate.
- Keep progress docs current: add a `changelog/entries/unreleased/` entry in the same commit, and file remaining work in `backlog/` (code) or `user-tasks/` (human action). See the Team workflow section at the end of this file.

## Architecture: `apps/web` (Active Frontend)

This is the single React app that serves marketing, auth, the mail product, settings, and the developer surface.

- **Framework**: React Router v7 (routes defined in `apps/web/app/routes.ts`)
- **Runtime**: Vite + Cloudflare Workers. Client-rendered SPA (`ssr: false`) with build-time **prerendering** of public marketing pages for SEO (`apps/web/react-router.config.ts`). Authenticated routes (`/mail`, `/settings`) are client-only — not server-rendered per request.
- **State**: Jotai (atoms) + TanStack Query (server state)
- **Styling**: Tailwind CSS v4 — CSS-first config via `@theme` directive in `apps/web/app/globals.css`
- **Components**: shadcn/ui–derived in `apps/web/components/ui/`
- **Rich text**: Tiptap editor
- **i18n**: Paraglide JS (`apps/web/messages/` compiled to `paraglide/`)
- **Auth client**: `apps/web/lib/auth-client.ts` — exports `signIn`, `signUp`, `signOut`, `useSession`
- **API calls**: tRPC client via `@trpc/tanstack-react-query` against `apps/server`
- **Env vars**: Vite prefix `VITE_PUBLIC_*`; `VITE_PUBLIC_BACKEND_URL` points to the server
- **Build/deploy**: `bun run --filter=@zero/web build`, `bun run --filter=@zero/web deploy` (see warning above re: stale root scripts)

Key route surfaces (from `apps/web/app/routes.ts`):
- `/` → landing, `/home`, `/about`, `/pricing`, `/terms`, `/privacy`, `/downloads`, `/contact`, `/faq`, `/hr`
- `/blog`, `/blog/:slug`, `/compare/:competitor`, `/share/:slug`, `/g/:token`
- `/login`, `/signup`
- `/developer`
- `/mail` (inbox), `/mail/:folder`, `/mail/compose`, `/mail/create`, `/mail/search`, `/mail/home`, `/mail/tasks`, `/mail/calendar`, `/mail/meetings`, `/mail/meetings/:id`, `/mail/docs`, `/mail/docs/:id`, `/mail/under-construction/:path`
- `/settings/*` — `general`, `appearance`, `ai`, `billing`, `calendars`, `categories`, `connections`, `danger-zone`, `design-system`, `labels`, `local-models`, `meetings`, `notifications`, `privacy`, `security`, `sharing`, `shortcuts`, `signatures`

## Architecture: `apps/server` (Backend)

- **Runtime**: Cloudflare Worker
- **HTTP framework**: Hono (`src/main.ts` is the entry point)
- **API layer**: tRPC router at `src/trpc/index.ts` — composed of per-domain routers in `src/trpc/routes/`
- **Database**: PostgreSQL via Drizzle ORM + Cloudflare Hyperdrive; schema at `src/db/schema.ts`
- **Auth**: Better Auth (`src/lib/auth.ts`) — Google OAuth, Apple Sign In, Email OTP, phone number, email/password (with email verification required). Microsoft commented out.
- **Durable Objects**: `ZeroDriver`, `ZeroAgent`, `ZeroDB`, `ZeroMCP`, `ShardRegistry`, `WorkflowRunner`, `ThreadSyncWorker`, `ThinkingMCP`
- **Cloudflare Workflows**: `SyncThreadsWorkflow`, `SyncThreadsCoordinatorWorkflow` — async email sync orchestration
- **Cloudflare**: KV namespaces, Queues, Workflows; all bindings in `wrangler.jsonc`
- **Deploy**: `bun deploy:backend` → Wrangler (`wrangler.jsonc`)
- **Dev utilities**: `bun test:ai`, `bun eval`, `bun eval:dev`, `bun eval:ci`

tRPC router **files** in `src/trpc/routes/` (one per domain): `ai`, `assistant`, `avatar`, `bimi`, `brain`, `calendar`, `categories`, `connections`, `contact`, `cookies`, `docs`, `drafts`, `groups`, `label`, `logging`, `mail`, `mail-assistant`, `meet`, `mentions`, `notes`, `sessions`, `settings`, `sharing`, `shortcut`, `subscription`, `tasks`, `templates`, `user`.

⚠️ **Client mount keys ≠ file names** for some routers (composed in `src/trpc/index.ts`) — call these from the client: `cookies.ts`→`cookiePreferences`, `label.ts`→`labels`, `mail-assistant.ts`→`mailAssistant`; and `tasks.ts` exports **both** `tasks` **and** `folders`. Full mount-key catalog: [docs/api.md](docs/api.md).

## Architecture: `apps/ios` (Native iOS)

- **Language**: Swift 6 / SwiftUI (strict concurrency)
- **Min iOS**: 18.0
- **Project file**: `apps/ios/Todus/Todus.xcodeproj`
- **Bundle ID**: `com.ludvighedin.todus`
- **Deep link scheme**: `todus://`
- **SPM Dependencies**: CalendarKit v1.1.7; also `packages/swift-auth` and `packages/swift-widgets` (monorepo SPM packages)
- **Auth**: Native OAuth flows (Google, Apple) + Email OTP — auth tokens extracted natively, then passed to the backend via Bearer token. **Do not use WKWebView fetch for cross-origin API calls** — use native URLSession instead.
- **Build commands**: `bun ios`, `bun ios:simulator`, `bun ios:build:preview`, `bun ios:build:production`

### iOS Services Layer
- `AuthService` — Better-Auth client (Apple Sign In, Google OAuth, Email OTP). Bearer token stored in Keychain.
- `TodosAPIClient` — Unified HTTP client for all tRPC backend calls. Adds `Authorization: Bearer <token>` header. Format: `POST /api/trpc/{procedure}` with Superjson wrapping.
- `EmailService` — Email inbox state, thread loading, actions (archive, read/unread). Wraps TodosAPIClient.
- `AIChatService` — SSE streaming chat, task mutations via tool calls, conversation history persistence, model selection.
- `CalendarService` — Shared EKEventStore access for calendar events.
- `TaskCaptureService` — Parses user input (remote-first with local NLP fallback), creates tasks in SwiftData.
- `AppleRemindersSyncService` — Bidirectional sync between SwiftData tasks and Apple Reminders.

### iOS Auth Flows
1. **Apple Sign In**: `ASAuthorizationAppleIDProvider` → ID token → `POST /api/auth/sign-in/social` with `{ provider: "apple", idToken }` → Bearer token → Keychain
2. **Google Sign In**: `ASWebAuthenticationSession` → backend Google OAuth → redirects to `/api/auth/mobile-token` → generates Bearer token → redirects to `todus://auth-callback?token=<bearer>` → Keychain
3. **Email OTP**: User enters email → `POST /api/auth/email-otp/send-verification-otp` → backend sends 6-digit code via Resend → user enters code → `POST /api/auth/email-otp/verify-email` → Bearer token → Keychain

### iOS Data Layer
- **SwiftData**: `TaskRecord`, `FolderRecord` — local task cache with offline support
- **In-memory**: `EmailThread`, `EmailMessage` — fetched from backend API, not persisted locally
- **EventKit**: `EKEvent` — system calendar, managed by CalendarKit
- **State**: `@Observable` AppServices singleton + `@Environment` injection + SwiftData `@Query`

## Shared Packages (`packages/`)

| Package | Purpose |
|---------|---------|
| `packages/shared` | Types and utilities shared across web + server |
| `packages/api-client` | HTTP client for tRPC API calls |
| `packages/ui-native` | Shared React Native UI components |
| `packages/design-tokens` | Theme and design constants |
| `packages/macos-doc-editor` | macOS-specific editor component library |
| `packages/cli` | `nizzy` CLI — workspace sync utilities; runs as `postinstall` |
| `packages/swift-auth` | SPM package: Swift auth utilities for iOS/macOS |
| `packages/swift-widgets` | SPM package: Swift widget extensions |
| `packages/testing` | Vitest test suite |
| `packages/tsconfig` | Shared TypeScript configs |
| `packages/eslint-config` | Shared ESLint config |

## Auth System

- **Provider**: Better Auth (server: `apps/server/src/lib/auth.ts`)
- **Providers enabled**: Google OAuth, Apple Sign In, Email OTP (via Resend), phone number (via Twilio), email/password (with email verification required). Microsoft commented out.
- **Client (web)**: `apps/web/lib/auth-client.ts`
- **Client (iOS)**: `apps/ios/Todus/Todus/Services/Auth/AuthService.swift`
- **Client (macOS)**: `apps/macos/TodusMac/Services/Auth/AuthService.swift`
- **`trustedOrigins`**: Hardcoded in `createAuthConfig()` — must be updated when adding new origins
- **Production domain**: `todus.app`; `COOKIE_DOMAIN=todus.app` in `apps/server/wrangler.jsonc`
- **Native session separation**: `/api/auth/mobile-token` creates a dedicated DB `session` row for the iOS/macOS app so it appears separately under "Active Sessions" instead of sharing the web OAuth session (falls back to the web token if the DB insert fails).

## Environment Variables

Frontend (`apps/web`): use `VITE_PUBLIC_` prefix.
Backend (`apps/server`): defined in `wrangler.jsonc`; type-safe via `src/env.ts`.
Local dev: use a `.env` file at root (loaded via `dotenv-cli`).

## Documentation Files

`.md` files to keep current when making architectural changes:
- `AGENT_CONTEXT.md` — canonical agent reference (this file's mirror, broader audience)
- `AGENTS.md` — agent-agnostic mirror
- `changelog/entries/unreleased/` — one file per shipped item, written in the same commit (`CHANGELOG.md` is now a pointer stub)
- `backlog/tasks/open/` — code follow-ups (`TASK.md` and `CODE_REVIEW_BACKLOG.md` are now pointer stubs)
- `user-tasks/tasks/open/` — work only the owner can do
- `docs/agent-memory/` — durable gotchas + `active-work.md` file claims + `regressions.md`
- `PRD.md` — product requirements (user flows, screens, empty states)
- `APPS_ARCHITECTURE.md` — canonical app surface (update when adding/removing apps)
- `DESIGN_SYSTEM.md` / `DESIGN_SYSTEM_INCONSISTENCIES.md` — design tokens + drift
- `PLANNING.md` / `ROADMAP.md` — feature planning (mostly historical)

See [AGENT_CONTEXT.md §10](AGENT_CONTEXT.md#10-documentation-map) for the full doc map and which files to ignore.

---

## Team workflow (agent operating system)

Several agents and humans share this repo, this working tree, and one branch. The
structure below exists so that work is never lost and never silently duplicated.

| What | Where | Who acts |
|------|-------|----------|
| Code / agent follow-ups, bugs, nits, deferred work | [`backlog/`](backlog/README.md) | an agent, autonomously |
| Work outside the codebase (env vars, dashboards, signing, accounts, live verification) | [`user-tasks/`](user-tasks/README.md) | the owner |
| History — what shipped | [`changelog/`](changelog/README.md) | written at commit time |
| Durable shared facts, gotchas, coordination | [`docs/agent-memory/`](docs/agent-memory/README.md) | anyone who learns one |

Plans are intent · feature docs are reality · backlog is remaining work · Git is history.
Never conflate them, and never keep two canonical docs for one topic.

1. **Branch policy.** Work on `main`. **Never create or switch branches unless the owner
   asks.** Verify with `git rev-parse --abbrev-ref HEAD` before committing.

2. **Stay in your lane.** Touch only the files your task needs; never reformat unrelated
   code. **Never `git add .` or `git add -A`** — stage owned paths explicitly. Claim your
   files in [`docs/agent-memory/active-work.md`](docs/agent-memory/active-work.md) and
   scan it for overlap before you start. If pending changes conflict with yours, stop and
   report.

3. **Document as you go.** After any meaningful change, update the canonical doc for it
   (`AGENT_CONTEXT.md`, `FEATURES.md`, `DESIGN_SYSTEM.md`, the `docs/` reference set).
   Any new doc must be registered in [`docs/README.md`](docs/README.md). Plans live only
   in `docs/plans/{open,doing,done,archive}/`.

4. **Review before push.** Self-review the diff. Spawn a reviewer subagent for anything
   touching auth, payments, schema, webhooks, security, or 3+ files.

5. **Commit + changelog together.** One entry file per meaningful item in
   `changelog/entries/unreleased/`, written in the **same commit** as the change. Get the
   id from `bun changelog:check` — never by eye.

6. **Track follow-ups.** Code work → `backlog/`. Human hands → `user-tasks/`. Scope,
   priority and risk decisions → ask the owner. **Never bury a human action item in
   `backlog/`.** Closing an item means moving it to `tasks/done/`, flipping `status`, and
   appending a dated note with **evidence** — what you observed, not what should be true.

7. **Verify before finishing.** Run what your change touched:

   ```bash
   bun run test                          # vitest (packages/testing)
   bun run --filter=@zero/server test:ai # backend AI tests
   npx eslint <file>                     # per-file — never bun lint / bun check
   npx prettier --write <file>           # per-file — never bun format
   bun run --filter=@zero/web build      # the real frontend build
   bun agent-ops:check                   # backlog / user-tasks / changelog / docs integrity
   ```

   iOS: `bun ios:simulator`. macOS: `bun macos`. Never run repo-wide lint or format, and
   don't start a heavy gate another session is already running.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Monorepo Structure

This is a **pnpm + Turborepo** monorepo. The active apps are:

| App | Path | Stack | Purpose |
|-----|------|-------|---------|
| Web | `apps/mail` | React Router v7 + Vite + Cloudflare Workers | Main web product |
| Backend | `apps/server` | Cloudflare Worker (Hono + tRPC + Durable Objects) | Auth, mail APIs, AI workflows |
| iOS | `apps/ios/Todus` | Native SwiftUI (Xcode) | iPhone app |
| macOS | `apps/macos` | Native SwiftUI (Xcode, Swift 6) | Desktop shell scaffold with sidebar navigation |

**Do not use** anything under `apps/archived/` — those are reference-only legacy implementations.

## Key Commands

```bash
# Development
pnpm go                         # Start Docker DB + web + backend
pnpm dev                        # Start web + backend dev servers
pnpm web                        # Alias for web + backend dev servers
pnpm mail                       # Start the web app only
pnpm docker:db:up               # Start PostgreSQL in Docker
pnpm docker:db:stop             # Stop PostgreSQL
pnpm docker:db:down             # Remove PostgreSQL container
pnpm docker:db:clean            # Remove PostgreSQL container and volumes
pnpm ios                        # Start the iOS app
pnpm ios:simulator              # Launch the iOS simulator flow
pnpm ios:build:preview          # Build iOS preview artifact
pnpm ios:build:production       # Build iOS production artifact
pnpm macos                      # Start the macOS app
pnpm android                    # Start the Android app
pnpm scripts                    # Run repo scripts via tsx

# Database
pnpm db:generate                # Generate migration from schema changes
pnpm db:migrate                 # Apply migrations
pnpm db:push                    # Push schema changes directly
pnpm db:studio                  # Drizzle Studio GUI

# Build & Deploy
pnpm build                      # Build all packages
pnpm build:frontend             # Build the web app only
pnpm deploy:frontend            # Deploy web to Cloudflare
pnpm deploy:backend             # Deploy backend to Cloudflare Workers
pnpm sentry:sourcemaps          # Upload frontend source maps

# Evaluations and parity
pnpm test:ai                    # Run backend AI tests
pnpm eval                       # Run backend evals
pnpm eval:dev                   # Run backend evals in dev mode
pnpm eval:ci                    # Run backend evals in CI mode
pnpm parity:screenshots:check   # Compare screenshot parity
pnpm parity:screenshots:sync    # Sync screenshot logs
pnpm parity:screenshots:capture:ios
pnpm parity:screenshots:capture:ios:auto
pnpm parity:screenshots:capture:android:auto
pnpm parity:screenshots:capture:macos:auto

# Quality
pnpm precommit                 # Local pre-commit lint gate
pnpm lint                      # ESLint
pnpm format                    # Prettier write for app code
pnpm check                     # Format check + lint
pnpm check:format              # Prettier check
pnpm test                      # Run tests
pnpm test:watch                # Watch tests
pnpm test:coverage             # Coverage run
pnpm test:ui                   # UI test runner
pnpm test -- -t "test name"     # Single test
```

### Important Restrictions
- **NEVER run project-wide lint/format commands** (`pnpm check`, `pnpm lint`, `pnpm format`) — these touch the entire codebase. Only lint/format specific files you changed. Use file-scoped formatting or targeted test commands instead.

### Current Workflow Notes
- Prefer `pnpm go` when you need the full local stack; it brings up Docker Postgres before the app processes.
- Use `pnpm dev` for the web/backend loop when the database is already running.
- Use `pnpm mail` when only the web frontend needs to move.
- Use `pnpm ios:simulator` for simulator debugging, but `pnpm ios` is the lighter app-start command.
- Use `pnpm macos` for the native macOS shell; the old Electron-based flow is obsolete.
- When adding schema changes, keep the order `db:generate` -> review migration -> `db:migrate` or `db:push` as appropriate.
- Keep progress docs current: update `CHANGELOG.md`, `TASK.md`, `PLANNING.md`, or `ROADMAP.md` when work changes behavior or architecture.

## Architecture: `apps/mail` (Web Frontend)

- **Framework**: React Router v7 (file-based routes defined in `app/routes.ts`)
- **State**: Jotai (atoms) + TanStack Query (server state)
- **Styling**: Tailwind CSS v4 + shadcn/ui components
- **Rich text**: Tiptap editor
- **i18n**: Paraglide JS (`apps/mail/messages/`, compiled to `paraglide/`)
- **Auth client**: `apps/mail/lib/auth-client.ts` — exports `signIn`, `signUp`, `signOut`, `useSession`
- **API calls**: tRPC client via `@trpc/tanstack-react-query`
- **Env vars**: Vite prefix `VITE_PUBLIC_*`; `VITE_PUBLIC_BACKEND_URL` points to the server
- **Build/deploy**: `pnpm build:frontend`, `pnpm deploy:frontend`, `pnpm sentry:sourcemaps`

Routes are defined in `app/routes.ts`. The main mail UI lives under `/mail/:folder`.

## Architecture: `apps/server` (Backend)

- **Runtime**: Cloudflare Worker
- **HTTP framework**: Hono (`src/main.ts` is the entry point)
- **API layer**: tRPC router at `src/trpc/index.ts` — composed of per-domain routers in `src/trpc/routes/`
- **Database**: PostgreSQL via Drizzle ORM + Cloudflare Hyperdrive; schema at `src/db/schema.ts`
- **Auth**: Better Auth (`src/lib/auth.ts`) — Google OAuth, Apple Sign In, Email OTP, phone number, email/password (with email verification required)
- **Durable Objects**: `ZeroDriver`, `ZeroAgent`, `ZeroDB`, `ZeroMCP`, `ShardRegistry`, `WorkflowRunner`, `ThreadSyncWorker`
- **Cloudflare**: KV namespaces, Queues, Workflows for async email sync
- **Deploy**: `pnpm deploy:backend` → Wrangler (`wrangler.jsonc`)
- **Dev utilities**: `pnpm test:ai`, `pnpm eval`, `pnpm eval:dev`, `pnpm eval:ci`

tRPC routes mirror the `src/trpc/routes/` filenames: `mail`, `ai`, `settings`, `connections`, `labels`, `categories`, `drafts`, `notes`, `tasks`, etc.

## Architecture: `apps/ios` (Native iOS)

- **Language**: Swift 6 / SwiftUI (strict concurrency)
- **Min iOS**: 18.0
- **Project file**: `apps/ios/Todus/Todus.xcodeproj`
- **Bundle ID**: `com.ludvighedin.todus`
- **Deep link scheme**: `todus://`
- **SPM Dependencies**: CalendarKit v1.1.7
- **Auth**: Native OAuth flows (Google, Apple) + Email OTP — auth tokens extracted natively, then passed to the backend via Bearer token. **Do not use WKWebView fetch for cross-origin API calls** — use native URLSession instead.
- **Build commands**: `pnpm ios`, `pnpm ios:simulator`, `pnpm ios:build:preview`, `pnpm ios:build:production`

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
| `packages/ui-native` | Shared React Native UI components |
| `packages/testing` | Vitest test suite |
| `packages/tsconfig` | Shared TypeScript configs |
| `packages/eslint-config` | Shared ESLint config |

## Auth System

- **Provider**: Better Auth (server: `apps/server/src/lib/auth.ts`)
- **Providers enabled**: Google OAuth, Apple Sign In, Email OTP (via Resend), phone number (via Twilio), email/password (with email verification required). Microsoft commented out.
- **Client (web)**: `apps/mail/lib/auth-client.ts`
- **Client (iOS)**: `apps/ios/Todus/Todus/Services/Auth/AuthService.swift`
- **`trustedOrigins`**: Hardcoded in `createAuthConfig()` — must be updated when adding new origins
- **Production domain**: `todus.app`; `COOKIE_DOMAIN=todus.app` in `apps/server/wrangler.jsonc`

## Environment Variables

Frontend (`apps/mail`): use `VITE_PUBLIC_` prefix.
Backend (`apps/server`): defined in `wrangler.jsonc`; type-safe via `src/env.ts`.
Local dev: use a `.env` file at root (loaded via `dotenv-cli`).

## Documentation Files

Several `.md` files track ongoing work — keep them updated when making architectural changes:
- `CHANGELOG.md` — log all significant changes
- `TASK.md` — current task status
- `PLANNING.md` / `ROADMAP.md` — feature planning
- `APPS_ARCHITECTURE.md` — canonical app surface (update if adding/removing apps)

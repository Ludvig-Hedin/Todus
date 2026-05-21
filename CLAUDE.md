# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Monorepo Structure

This is a **pnpm + Turborepo** monorepo. The active apps are:

| App | Path | Stack | Purpose |
|-----|------|-------|---------|
| Mail product | `apps/web` | React Router v7 + Vite + Cloudflare Workers | The deployed email client UI (primary — all frontend work goes here) |
| ~~Mail product (legacy)~~ | `apps/mail` | React Router v7 + Vite + Cloudflare Workers | **READ-ONLY. Do not edit.** Superseded by `apps/web`. |
| Backend | `apps/server` | Cloudflare Worker (Hono + tRPC + Durable Objects) | Auth, mail APIs, AI workflows |
| iOS | `apps/ios/Todus` | Native SwiftUI (Xcode) | iPhone app |
| macOS | `apps/macos` | Native SwiftUI (Xcode, Swift 6) | Desktop shell with sidebar navigation |

**Do not use** anything under `apps/archived/` — those are reference-only legacy implementations.

> **IMPORTANT — `apps/mail/` is READ-ONLY.**
> All frontend work now lives in `apps/web/`. Never edit any file under `apps/mail/`. Treat it as an archived reference. If you need to make a frontend change, make it in `apps/web/` instead.

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
pnpm go                         # Start Docker DB + apps/web + backend (full local stack)
pnpm dev                        # Start apps/web + backend (DB must already be running)
pnpm web                        # Alias for pnpm dev
pnpm mail                       # Start apps/mail (mail product) only
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
pnpm build:frontend             # Build apps/mail (the deployed mail product)
pnpm deploy:frontend            # Deploy apps/mail to Cloudflare
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
pnpm precommit                 # Run oxlint --deny-warnings on staged files
pnpm lint                      # ESLint (turbo)
pnpm format                    # Prettier write for app code
pnpm check                     # Format check + lint
pnpm check:format              # Prettier check
pnpm test                      # Run tests (packages/testing)
pnpm test:watch                # Watch tests
pnpm test:coverage             # Coverage run
pnpm test:ui                   # UI test runner
pnpm test -- -t "test name"     # Single test
```

### Important Restrictions
- **NEVER run project-wide lint/format commands** (`pnpm check`, `pnpm lint`, `pnpm format`) — these touch the entire codebase. Only lint/format specific files you changed.

### Current Workflow Notes
- `pnpm dev` / `pnpm web` starts the **marketing site** (`apps/web`) + backend. Use `pnpm mail` to develop the mail product UI (`apps/mail`).
- Prefer `pnpm go` when you need the full local stack; it brings up Docker Postgres before the app processes.
- Use `pnpm ios:simulator` for simulator debugging, but `pnpm ios` is the lighter app-start command.
- Use `pnpm macos` for the native macOS shell; the old Electron-based flow is obsolete.
- When adding schema changes, keep the order `db:generate` → review migration → `db:migrate` or `db:push` as appropriate.
- Keep progress docs current: update `CHANGELOG.md`, `TASK.md`, `PLANNING.md`, or `ROADMAP.md` when work changes behavior or architecture.

## Architecture: `apps/mail` (Mail Product UI)

- **Framework**: React Router v7 (routes defined in `app/routes.ts`)
- **State**: Jotai (atoms) + TanStack Query (server state)
- **Styling**: Tailwind CSS v4 — CSS-first config via `@theme` directive in CSS, not `tailwind.config.js`
- **Rich text**: Tiptap editor
- **i18n**: Paraglide JS (`apps/mail/messages/`, compiled to `paraglide/`)
- **Auth client**: `apps/mail/lib/auth-client.ts` — exports `signIn`, `signUp`, `signOut`, `useSession`
- **API calls**: tRPC client via `@trpc/tanstack-react-query`
- **Env vars**: Vite prefix `VITE_PUBLIC_*`; `VITE_PUBLIC_BACKEND_URL` points to the server
- **Build/deploy**: `pnpm build:frontend`, `pnpm deploy:frontend`, `pnpm sentry:sourcemaps`

Routes are defined in `app/routes.ts`. The main mail UI lives under `/mail/:folder`.

## Architecture: `apps/web` (Marketing Site)

- **Framework**: React Router v7 (same stack as `apps/mail`)
- **Routes**: Landing (`/`), `/home`, `/about`, `/pricing`, `/terms`, `/privacy`, `/blog/:slug`, `/compare/:competitor`
- Started by `pnpm dev` / `pnpm web`; **not** deployed by `deploy:frontend` (which targets `apps/mail`)

## Architecture: `apps/server` (Backend)

- **Runtime**: Cloudflare Worker
- **HTTP framework**: Hono (`src/main.ts` is the entry point)
- **API layer**: tRPC router at `src/trpc/index.ts` — composed of per-domain routers in `src/trpc/routes/`
- **Database**: PostgreSQL via Drizzle ORM + Cloudflare Hyperdrive; schema at `src/db/schema.ts`
- **Auth**: Better Auth (`src/lib/auth.ts`) — Google OAuth, Apple Sign In, Email OTP, phone number, email/password (with email verification required). Microsoft commented out.
- **Durable Objects**: `ZeroDriver`, `ZeroAgent`, `ZeroDB`, `ZeroMCP`, `ShardRegistry`, `WorkflowRunner`, `ThreadSyncWorker`, `ThinkingMCP`
- **Cloudflare Workflows**: `SyncThreadsWorkflow`, `SyncThreadsCoordinatorWorkflow` — async email sync orchestration
- **Cloudflare**: KV namespaces, Queues, Workflows; all bindings in `wrangler.jsonc`
- **Deploy**: `pnpm deploy:backend` → Wrangler (`wrangler.jsonc`)
- **Dev utilities**: `pnpm test:ai`, `pnpm eval`, `pnpm eval:dev`, `pnpm eval:ci`

tRPC routers in `src/trpc/routes/`: `assistant`, `ai`, `avatar`, `bimi`, `brain`, `calendar`, `categories`, `connections`, `cookiePreferences`, `drafts`, `folders`, `groups`, `labels`, `logging`, `mail`, `mailAssistant`, `meet`, `mentions`, `notes`, `sessions`, `settings`, `sharing`, `shortcut`, `subscription`, `tasks`, `templates`, `user`, `docs`.

## Architecture: `apps/ios` (Native iOS)

- **Language**: Swift 6 / SwiftUI (strict concurrency)
- **Min iOS**: 18.0
- **Project file**: `apps/ios/Todus/Todus.xcodeproj`
- **Bundle ID**: `com.ludvighedin.todus`
- **Deep link scheme**: `todus://`
- **SPM Dependencies**: CalendarKit v1.1.7; also `packages/swift-auth` and `packages/swift-widgets` (monorepo SPM packages)
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
- **Client (web)**: `apps/mail/lib/auth-client.ts`
- **Client (iOS)**: `apps/ios/Todus/Todus/Services/Auth/AuthService.swift`
- **`trustedOrigins`**: Hardcoded in `createAuthConfig()` — must be updated when adding new origins
- **Production domain**: `todus.app`; `COOKIE_DOMAIN=todus.app` in `apps/server/wrangler.jsonc`

## Environment Variables

Frontend (`apps/mail`, `apps/web`): use `VITE_PUBLIC_` prefix.
Backend (`apps/server`): defined in `wrangler.jsonc`; type-safe via `src/env.ts`.
Local dev: use a `.env` file at root (loaded via `dotenv-cli`).

## Documentation Files

Several `.md` files track ongoing work — keep them updated when making architectural changes:
- `CHANGELOG.md` — log all significant changes
- `TASK.md` — current task status
- `PLANNING.md` / `ROADMAP.md` — feature planning
- `APPS_ARCHITECTURE.md` — canonical app surface (update if adding/removing apps)

# Todus — Agent Configuration

> For all AI coding agents (Claude, Cursor, Gemini, Copilot, etc.). Last updated: March 31, 2026.

Todus is a unified productivity app — email, calendar, tasks, and AI assistant in one app. Built as a **pnpm + Turborepo** monorepo.

---

## Active Apps

| App | Path | Stack | Purpose |
|-----|------|-------|---------|
| **Web** | `apps/web` | React Router v7 + Vite + Cloudflare Workers | Main web product at todus.app |
| **Backend** | `apps/server` | Cloudflare Worker (Hono + tRPC + Durable Objects) | Auth, mail APIs, AI, task sync |
| **iOS** | `apps/ios/Todus` | Native SwiftUI (Xcode, Swift 6) | iPhone app |
| **macOS** | `apps/macos` | Native SwiftUI (Xcode, Swift 6) | Desktop shell scaffold with sidebar navigation |

**Do not use** anything under `apps/archived/` — reference-only legacy code.

---

## Design System

Cross-platform design tokens are documented and tracked. **Update these when you change colors, typography, radius, spacing, or motion.**

- **Canonical reference:** [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) — tokens, accent palette, component cross-reference, "how to change"
- **Known gaps:** [DESIGN_SYSTEM_INCONSISTENCIES.md](DESIGN_SYSTEM_INCONSISTENCIES.md) — drift, resolved + open
- **Live viewers** (gated to `TODUS_ALLOWLISTED_EMAILS` / `VITE_TODUS_ALLOWLISTED_EMAILS`):
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

---

## Commands

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

# Database (Drizzle ORM)
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
pnpm test -- -t "name"         # Single test
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

---

## Backend Architecture (`apps/server`)

- **Runtime:** Cloudflare Worker
- **HTTP framework:** Hono (`src/main.ts` entry point)
- **API layer:** tRPC router at `src/trpc/index.ts`, per-domain routers in `src/trpc/routes/`
- **Database:** PostgreSQL via Drizzle ORM + Cloudflare Hyperdrive. Schema: `src/db/schema.ts`
- **Auth:** Better Auth (`src/lib/auth.ts`) — Google OAuth, Apple Sign In, Email OTP, Bearer plugin, JWT plugin
- **Durable Objects:** ZeroDriver, ZeroAgent, ZeroDB, ZeroMCP, ShardRegistry, WorkflowRunner, ThreadSyncWorker
- **Infrastructure:** KV namespaces, Queues, Workflows for async email sync
- **Deploy:** `pnpm deploy:backend` → Wrangler (`wrangler.jsonc`)
- **Dev utilities:** `pnpm test:ai`, `pnpm eval`, `pnpm eval:dev`, `pnpm eval:ci`

### tRPC Routes
Routes mirror filenames in `src/trpc/routes/`: `mail`, `ai`, `settings`, `connections`, `labels`, `categories`, `drafts`, `notes`, `tasks`, `templates`, `user`, `avatar`, `bimi`, `brain`, `cookies`, `label`, `logging`, `meet`, `shortcut`

### Database Schema (Key Tables)
`user`, `session`, `account`, `verification`, `connection`, `task`, `taskFolder`, `emailTemplate`, `userSettings`, `userHotkeys`, `note`, `oauthApplication`, `oauthAccessToken`, `oauthConsent`, `earlyAccess`, `jwks`, `summary`, `writingStyleMatrix`

---

## Web Frontend Architecture (`apps/mail`)

- **Framework:** React Router v7 (file-based routes in `app/routes.ts`)
- **State:** Jotai (atoms) + TanStack Query (server state)
- **Styling:** Tailwind CSS v4 + shadcn/ui components
- **Rich text:** Tiptap editor
- **i18n:** Paraglide JS (`messages/` → compiled to `paraglide/`)
- **Auth client:** `lib/auth-client.ts` — exports `signIn`, `signUp`, `signOut`, `useSession`
- **API calls:** tRPC client via `@trpc/tanstack-react-query`
- **Env vars:** Vite prefix `VITE_PUBLIC_*`; `VITE_PUBLIC_BACKEND_URL` points to the server
- **Build/deploy:** `pnpm build:frontend`, `pnpm deploy:frontend`, `pnpm sentry:sourcemaps`

Main mail UI route: `/mail/:folder`

---

## iOS Architecture (`apps/ios/Todus`)

- **Language:** Swift 6 / SwiftUI (strict concurrency)
- **Min iOS:** 18.0
- **Project file:** `apps/ios/Todus/Todus.xcodeproj`
- **Bundle ID:** `com.ludvighedin.todus`
- **Deep link scheme:** `todus://`
- **SPM dependency:** CalendarKit v1.1.7

### App Structure
```
Todus/
  App/           → TodosApp.swift (@main), AppServices.swift (DI container), RootView.swift
  Navigation/    → MainTabView.swift, AppTab.swift, CustomTabBar.swift, CreateSheet.swift
  Features/
    Home/        → HomeView.swift (today dashboard)
    Tasks/       → TasksTabView, InboxView, BoardView, TaskTableView, CalendarTaskView, TaskRowView, TaskDetailSheet, CaptureComposer
    Email/       → EmailInboxView, EmailThreadView, EmailComposeView, EmailConnectView, EmailRowView, SenderAvatarView
    Calendar/    → CalendarContainerView (UIKit bridge), CalendarViewController, EKWrapper
    AI/          → AIChatView (streaming chat sheet), AIChatMessage
    Auth/        → AuthView (Google + Apple sign-in), OnboardingAuthSheet
    Settings/    → SettingsView, RemindersSetupView, GmailOnboardingView
    Folders/     → FolderManagementView, MoveToFolderSheet
    Voice/       → VoiceInputButton
  Services/
    Auth/        → AuthService (Better-Auth, Keychain token), AuthSessionStore (legacy)
    API/         → TodosAPIClient (unified TRPC-over-HTTP with Bearer auth)
    Email/       → EmailService (inbox state, thread loading, actions)
    AI/          → AIChatService (SSE streaming, tool calls, conversation history)
    Calendar/    → CalendarService (shared EKEventStore)
    Tasks/       → TaskCaptureService, SupabaseSyncService (legacy)
    Reminders/   → AppleRemindersSyncService, RemindersSyncState
    Parsing/     → LocalTaskParsingService, RemoteFirstTaskParsingService
  Domain/        → EmailModels, TaskStatus, AppTaskPriority, TaskViewMode, SyncModels, AIChatConversation, etc.
  Data/          → TaskRecord (SwiftData), FolderRecord (SwiftData), AppConfiguration
  DesignSystem/  → AppTheme (colors, typography), BrandIcons, Formatters
```

### Key Patterns
- **State management:** `@Observable` (AppServices singleton) + `@Environment` injection + SwiftData `@Query`
- **API calls:** `TodosAPIClient` wraps URLSession, adds Bearer token, talks tRPC-over-HTTP (POST `/api/trpc/{procedure}`, Superjson format)
- **Auth:** Native Apple Sign In → ID token → backend. Google via ASWebAuthenticationSession → backend OAuth → deep link callback. Email OTP via Resend.
- **DO NOT use WKWebView fetch for cross-origin API calls** — use native URLSession instead.
- **Build commands:** `pnpm ios`, `pnpm ios:simulator`, `pnpm ios:build:preview`, `pnpm ios:build:production`

---

## Auth System

- **Provider:** Better Auth (server: `apps/server/src/lib/auth.ts`)
- **Sign-in methods:** Google OAuth, Apple Sign In (native), Email OTP (via Resend)
- **Plugins:** Bearer, JWT, Phone Number (adapted for email OTP)
- **Client (web):** `apps/mail/lib/auth-client.ts`
- **Client (iOS):** `AuthService.swift` → Keychain for Bearer token
- **`trustedOrigins`:** Hardcoded in `createAuthConfig()` — must update when adding new origins
- **Production domain:** `todus.app`; `COOKIE_DOMAIN=todus.app` in `wrangler.jsonc`
- **iOS deep link:** `todus://auth-callback` (for Google OAuth token handoff)
- **Bundle ID:** `com.ludvighedin.todus` (configured in Better Auth Apple provider)

---

## Environment Variables

- **Frontend (`apps/web`):** Use `VITE_PUBLIC_` prefix
- **Backend (`apps/server`):** Defined in `wrangler.jsonc`; type-safe via `src/env.ts`
- **Local dev:** `.env` at monorepo root (loaded via `dotenv-cli`)

Key variables: `BETTER_AUTH_SECRET`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `DATABASE_URL`, `RESEND_API_KEY`, `COOKIE_DOMAIN`

---

## Shared Packages (`packages/`)

| Package | Purpose |
|---------|---------|
| `packages/shared` | Types and utilities shared across web + server |
| `packages/testing` | Vitest test suite |
| `packages/tsconfig` | Shared TypeScript configs |
| `packages/eslint-config` | Shared ESLint config |

---

## Code Style

- 2-space indentation, single quotes, semicolons required
- 100 character line width
- TypeScript strict mode
- Prettier with sort-imports and Tailwind plugins
- Swift: follow existing patterns in the codebase (no SwiftLint configured)

---

## Documentation Files

| File | Purpose |
|------|---------|
| `PRD.md` | Product requirements (user flows, screen specs, empty states, notifications) |
| `CLAUDE.md` | Claude Code-specific instructions + architecture details |
| `AGENTS.md` | This file — agent-agnostic architecture reference |
| `APPS_ARCHITECTURE.md` | Canonical app surface map |
| `CHANGELOG.md` | Change log |
| `TASK.md` / `PLANNING.md` / `ROADMAP.md` | Current work tracking |

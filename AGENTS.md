# Todus — Agent Configuration

> For all AI coding agents (Claude, Cursor, Gemini, Copilot, etc.). Last updated: March 27, 2026.

Todus is a unified productivity app — email, calendar, tasks, and AI assistant in one app. Built as a **pnpm + Turborepo** monorepo.

---

## Active Apps

| App | Path | Stack | Purpose |
|-----|------|-------|---------|
| **Web** | `apps/mail` | React Router v7 + Vite + Cloudflare Workers | Main web product at todus.app |
| **Backend** | `apps/server` | Cloudflare Worker (Hono + tRPC + Durable Objects) | Auth, mail APIs, AI, task sync |
| **iOS** | `apps/ios/Todus` | Native SwiftUI (Xcode, Swift 6) | iPhone app |
| **macOS** | `apps/macos` | Electron WebView | Desktop shell wrapping `apps/mail` |

**Do not use** anything under `apps/archived/` — reference-only legacy code.

---

## Commands

```bash
# Development
pnpm go               # Start DB + all apps
pnpm dev              # Start web + backend dev servers
pnpm docker:db:up     # Start PostgreSQL in Docker
pnpm ios:simulator    # iOS simulator
pnpm macos            # macOS Electron app

# Database (Drizzle ORM)
pnpm db:generate      # Generate migration from schema changes
pnpm db:migrate       # Apply migrations
pnpm db:studio        # Drizzle Studio GUI

# Build & Deploy
pnpm build            # Build all packages
pnpm deploy:frontend  # Deploy web to Cloudflare
pnpm deploy:backend   # Deploy backend to Cloudflare Workers

# Quality
pnpm lint             # ESLint
pnpm format           # Prettier
pnpm test             # Run tests
pnpm test -- -t "name" # Single test
```

### Important Restrictions
- **NEVER run project-wide lint/format commands** (`pnpm check`, `pnpm lint`, `pnpm format`) — these touch the entire codebase. Only lint/format specific files you changed.

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

- **Frontend (`apps/mail`):** Use `VITE_PUBLIC_` prefix
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

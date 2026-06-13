# Todus — Agent Configuration

> For all AI coding agents (Claude, Cursor, Gemini, Copilot, Codex, etc.). Last updated: 2026-05-27.
>
> **New here?** Start with [AGENT_CONTEXT.md](AGENT_CONTEXT.md) — fuller repo map, feature index, recent shipped work, doc map. This file is the shorter agent-config primer.

Todus is a unified productivity app — email, calendar, tasks, docs, meetings, AI assistant — in one product. Built as a **pnpm + Turborepo** monorepo with a single Cloudflare Workers backend serving web + iOS + macOS clients.

---

## Active Apps

| App | Path | Stack | Purpose |
|-----|------|-------|---------|
| **Web** | `apps/web` | React Router v7 + Vite + Cloudflare Workers | Full frontend (marketing + auth + mail product + settings + developer surface) at todus.app |
| **Backend** | `apps/server` | Cloudflare Worker (Hono + tRPC + Durable Objects + Workflows) | Auth, mail APIs, AI, task sync, sync workflows |
| **iOS** | `apps/ios/Todus` | Native SwiftUI (Xcode, Swift 6, iOS 18+) | iPhone app |
| **macOS** | `apps/macos/TodusMac` | Native SwiftUI (Xcode, Swift 6, macOS 15+) | Desktop app, DMG distributed via Cloudflare R2 |

**Legacy / read-only**:
- `apps/mail/` — superseded by `apps/web/`. **Do not edit.** Older `pnpm build:frontend` / `pnpm deploy:frontend` root scripts still target this — use `pnpm --filter=@zero/web build|deploy` to ship the active app.
- `apps/archived/` — old RN-CLI / Electron / SwiftUI-WebView implementations. Reference only.

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
pnpm build                                # Turbo build all packages
pnpm --filter=@zero/web build             # Build apps/web (active frontend)
pnpm --filter=@zero/web deploy            # Deploy apps/web to Cloudflare
pnpm build:frontend                       # ⚠️ Builds the LEGACY apps/mail (root script not yet retargeted)
pnpm deploy:frontend                      # ⚠️ Deploys the LEGACY apps/mail
pnpm deploy:backend                       # Deploy backend to Cloudflare Workers
pnpm sentry:sourcemaps                    # Upload frontend source maps
./scripts/build-mac-dmg.sh                # macOS DMG: archive → sign → R2 upload

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
- Use `pnpm dev` for the web/backend loop when the database is already running. This runs `apps/web`, not `apps/mail`.
- `pnpm mail` runs the **legacy archive** `apps/mail` — only use to compare against the old code, never edit it.
- Use `pnpm ios:simulator` for simulator debugging, but `pnpm ios` is the lighter app-start command.
- Use `pnpm macos` for the native macOS app; the old Electron flow is obsolete.
- When adding schema changes, keep the order `db:generate` -> review migration -> `db:migrate` or `db:push` as appropriate.
- Keep progress docs current: update `CHANGELOG.md`, `TASK.md`, `PRD.md`, or `APPS_ARCHITECTURE.md` when work changes behavior or architecture. See [AGENT_CONTEXT.md §10](AGENT_CONTEXT.md#10-documentation-map) for the full doc map.

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
Router **files** in `src/trpc/routes/` (one per domain): `ai`, `assistant`, `avatar`, `bimi`, `brain`, `calendar`, `categories`, `connections`, `contact`, `cookies`, `docs`, `drafts`, `groups`, `label`, `logging`, `mail`, `mail-assistant`, `meet`, `mentions`, `notes`, `sessions`, `settings`, `sharing`, `shortcut`, `subscription`, `tasks`, `templates`, `user`.

⚠️ **Client mount keys ≠ file names** for some (composed in `src/trpc/index.ts`): `cookies.ts`→`cookiePreferences`, `label.ts`→`labels`, `mail-assistant.ts`→`mailAssistant`; `tasks.ts` exports **both** `tasks` and `folders`. Full catalog: [docs/api.md](docs/api.md).

### Database Schema (Key Tables)
`user`, `session`, `account`, `verification`, `connection`, `task`, `taskFolder`, `emailTemplate`, `userSettings`, `userHotkeys`, `note`, `oauthApplication`, `oauthAccessToken`, `oauthConsent`, `earlyAccess`, `jwks`, `summary`, `writingStyleMatrix`. Schema lives in `apps/server/src/db/schema.ts`; Zod validators in `apps/server/src/lib/schemas.ts`.

---

## Web Frontend Architecture (`apps/web`)

The active frontend. Serves marketing pages, auth, the mail product, the settings surface, the developer view, and gated dev tools — all in one React Router v7 app.

- **Framework:** React Router v7 (file-based routes in `app/routes.ts`)
- **Runtime:** Vite + Cloudflare Workers. Client-rendered SPA (`ssr: false`) + build-time prerender of public marketing pages for SEO (`apps/web/react-router.config.ts`) — not per-request SSR
- **State:** Jotai (atoms) + TanStack Query (server state)
- **Styling:** Tailwind CSS v4 (CSS-first `@theme` config in `app/globals.css`) + shadcn/ui-derived components
- **Rich text:** Tiptap editor
- **i18n:** Paraglide JS (`messages/` → compiled to `paraglide/`)
- **Auth client:** `apps/web/lib/auth-client.ts` — exports `signIn`, `signUp`, `signOut`, `useSession`
- **API calls:** tRPC client via `@trpc/tanstack-react-query` pointed at `apps/server`
- **Env vars:** Vite prefix `VITE_PUBLIC_*`; `VITE_PUBLIC_BACKEND_URL` points to the server
- **Build/deploy:** `pnpm --filter=@zero/web build` and `pnpm --filter=@zero/web deploy` (the root `build:frontend` / `deploy:frontend` scripts still target the legacy `apps/mail` archive)

Main route surfaces:
- `/` (landing), `/home`, `/about`, `/pricing`, `/terms`, `/privacy`, `/downloads`, `/contact`, `/faq`, `/hr`, `/blog`, `/blog/:slug`, `/compare/:competitor`, `/share/:slug`, `/g/:token`
- `/login`, `/signup`, `/developer`
- `/mail` → `/mail/:folder` (inbox/folders), `/mail/compose`, `/mail/create`, `/mail/search`, `/mail/home`, `/mail/tasks`, `/mail/calendar`, `/mail/meetings(/:id)`, `/mail/docs(/:id)`, `/mail/under-construction/:path`
- `/settings/*` (subpages: general, appearance, ai, billing, calendars, categories, connections, danger-zone, design-system, labels, local-models, meetings, notifications, privacy, security, sharing, shortcuts, signatures)

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
    Email/       → EmailInboxView, EmailThreadView, EmailComposeView, EmailConnectView, EmailRowView, SenderAvatarView, From picker
    Calendar/    → CalendarContainerView (UIKit bridge), CalendarViewController, EKWrapper
    AI/          → AIChatView (streaming chat sheet), AIChatMessage, model picker, local-models settings
    Auth/        → AuthView (Google + Apple sign-in), OnboardingAuthSheet
    Settings/    → SettingsView, BillingSettingsView, DesignSystem viewer, RemindersSetupView, GmailOnboardingView, AutomationPolicyView
    Folders/     → FolderManagementView, MoveToFolderSheet
    Voice/       → VoiceInputButton, VoiceChatView (modal)
    Docs/        → DocsListView, DocEditorView (DocsWebView wrapper around Tiptap)
    Meetings/    → MeetingsListView, MeetingDetailView
    Notifications/, Search/, MoreSheetView.swift, DesignSystem viewer
  Services/
    Auth/        → AuthService (Better-Auth, Keychain token)
    API/         → TodosAPIClient (unified tRPC-over-HTTP with Bearer auth)
    Email/       → EmailService (inbox state, thread loading, actions)
    AI/          → AIChatService (SSE streaming, tool calls, conversation history), Local/ (MLXInferenceService, LocalModelStateStore)
    Calendar/    → CalendarService (shared EKEventStore)
    Tasks/       → TaskCaptureService
    Reminders/   → AppleRemindersSyncService, RemindersSyncState
    Parsing/     → LocalTaskParsingService, RemoteFirstTaskParsingService, CompoundIntentParser
    Docs/        → DocsService (CRUD + search + workspace dedup)
    Drafts/      → Drafts service
    Voice/       → VoiceSessionCoordinator, VoiceSystemPromptClient, VoiceToolRegistry, VoiceAudioCapture, VoiceMicLock, VoiceIntent
    Meetings/    → Meetings service
    Subscription/, Notifications/, Widgets/, AppLogger.swift, NetworkMonitor.swift
  Domain/        → EmailModels, TaskStatus, AppTaskPriority, TaskViewMode, SyncModels, AIChatConversation, DocTypes, AssistantAutomationPolicy, etc.
  Data/          → TaskRecord (SwiftData), FolderRecord (SwiftData), AppConfiguration
  DesignSystem/  → AppTheme (colors, typography, motion, spacing), BrandIcons, Formatters
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
- **Sign-in methods:** Google OAuth, Apple Sign In (native), Email OTP (via Resend), Phone (via Twilio), email/password (verification required)
- **Plugins:** Bearer, JWT, Phone Number (adapted for email OTP)
- **Client (web):** `apps/web/lib/auth-client.ts`
- **Client (iOS):** `apps/ios/Todus/Todus/Services/Auth/AuthService.swift` → Keychain for Bearer token
- **Client (macOS):** `apps/macos/TodusMac/Services/Auth/AuthService.swift` → Keychain
- **`trustedOrigins`:** Hardcoded in `createAuthConfig()` — must update when adding new origins
- **Production domain:** `todus.app`; `COOKIE_DOMAIN=todus.app` in `wrangler.jsonc`
- **Native deep link:** `todus://auth-callback` (Google OAuth token handoff)
- **Bundle ID:** `com.ludvighedin.todus` (configured in Better Auth Apple provider)
- **Native session row:** `/api/auth/mobile-token` creates a dedicated `session` row for the native app so it appears as a separate "Active Session" in settings (falls back to the web session token if the insert fails).

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
| `packages/shared` | Types + utilities shared web ↔ server |
| `packages/api-client` | HTTP client for tRPC API calls |
| `packages/design-tokens` | Cross-platform design constants |
| `packages/ui-native` | Shared React Native UI components (legacy holdover) |
| `packages/macos-doc-editor` | Tiptap editor bundle embedded by macOS docs view |
| `packages/cli` | `nizzy` CLI — workspace sync utilities (runs as postinstall) |
| `packages/swift-auth` | SPM package — shared iOS/macOS auth + developer-access allowlist |
| `packages/swift-widgets` | SPM package — shared iOS/macOS widget extensions |
| `packages/testing` | Vitest test suite + Playwright E2E setup |
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
| `AGENT_CONTEXT.md` | **Canonical agent reference** — read first |
| `CLAUDE.md` | Claude Code–specific instructions + architecture details |
| `AGENTS.md` | This file — agent-agnostic architecture reference |
| `APPS_ARCHITECTURE.md` | Canonical app surface map (runtime targets, build entry points) |
| `FEATURES.md` / `FEATURE_TEST_PLAN.md` | Per-surface feature catalog + companion test checklist |
| `DESIGN_SYSTEM.md` / `DESIGN_SYSTEM_INCONSISTENCIES.md` | Design tokens + drift tracker |
| `PRD.md` | Product requirements (user flows, screen specs, empty states, notifications) |
| `CHANGELOG.md` | Change log (append to `[Unreleased]`) |
| `TASK.md` | Sprint task tracking |
| `CODE_REVIEW_BACKLOG.md` | Deferred fixes from bug hunts / reviews |
| `SELF_HOSTING.md`, `SECURITY.md`, `MCP.md`, `SCRIPTS_GUIDE.md` | Operational guides |
| `PLANNING.md` / `ROADMAP.md` | Historical migration + roadmap snapshots |

See [AGENT_CONTEXT.md §10](AGENT_CONTEXT.md#10-documentation-map) for the full doc map (active vs historical).

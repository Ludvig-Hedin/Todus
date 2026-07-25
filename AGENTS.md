# Todus — Agent Configuration

> For all AI coding agents (Claude, Cursor, Gemini, Copilot, Codex, etc.). Last updated: 2026-05-27.
>
> **New here?** Start with [AGENT_CONTEXT.md](AGENT_CONTEXT.md) — fuller repo map, feature index, recent shipped work, doc map. This file is the shorter agent-config primer.

Todus is a unified productivity app — email, calendar, tasks, docs, meetings, AI assistant — in one product. Built as a **bun + Turborepo** monorepo with a single Cloudflare Workers backend serving web + iOS + macOS clients.

---

## Active Apps

| App | Path | Stack | Purpose |
|-----|------|-------|---------|
| **Web** | `apps/web` | React Router v7 + Vite + Cloudflare Workers | Full frontend (marketing + auth + mail product + settings + developer surface) at todus.app |
| **Backend** | `apps/server` | Cloudflare Worker (Hono + tRPC + Durable Objects + Workflows) | Auth, mail APIs, AI, task sync, sync workflows |
| **iOS** | `apps/ios/Todus` | Native SwiftUI (Xcode, Swift 6, iOS 18+) | iPhone app |
| **macOS** | `apps/macos/TodusMac` | Native SwiftUI (Xcode, Swift 6, macOS 15+) | Desktop app, DMG distributed via Cloudflare R2 |

**Legacy / read-only**:
- `apps/mail/` — superseded by `apps/web/`. **Do not edit.** Older `bun build:frontend` / `bun deploy:frontend` root scripts still target this — use `bun run --filter=@zero/web build|deploy` to ship the active app.
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
bun go                         # Start Docker DB + web + backend
bun dev                        # Start web + backend dev servers
bun web                        # Alias for web + backend dev servers
bun mail                       # Start the web app only
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

# Database (Drizzle ORM)
bun db:generate                # Generate migration from schema changes
bun db:migrate                 # Apply migrations
bun db:push                    # Push schema changes directly
bun db:studio                  # Drizzle Studio GUI

# Build & Deploy
bun run build                                # Turbo build all packages
bun run --filter=@zero/web build             # Build apps/web (active frontend)
bun run --filter=@zero/web deploy            # Deploy apps/web to Cloudflare
bun build:frontend                       # ⚠️ Builds the LEGACY apps/mail (root script not yet retargeted)
bun deploy:frontend                      # ⚠️ Deploys the LEGACY apps/mail
bun deploy:backend                       # Deploy backend to Cloudflare Workers
bun sentry:sourcemaps                    # Upload frontend source maps
./scripts/build-mac-dmg.sh                # macOS DMG: archive → sign → R2 upload

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
bun precommit                 # Local pre-commit lint gate
bun lint                      # ESLint
bun format                    # Prettier write for app code
bun check                     # Format check + lint
bun check:format              # Prettier check
bun run test                      # Run tests
bun test:watch                # Watch tests
bun test:coverage             # Coverage run
bun test:ui                   # UI test runner
bun run test -- -t "name"         # Single test
```

### Important Restrictions
- **NEVER run project-wide lint/format commands** (`bun check`, `bun lint`, `bun format`) — these touch the entire codebase. Only lint/format specific files you changed. Use file-scoped formatting or targeted test commands instead.

### Current Workflow Notes
- Prefer `bun go` when you need the full local stack; it brings up Docker Postgres before the app processes.
- Use `bun dev` for the web/backend loop when the database is already running. This runs `apps/web`, not `apps/mail`.
- `bun mail` runs the **legacy archive** `apps/mail` — only use to compare against the old code, never edit it.
- Use `bun ios:simulator` for simulator debugging, but `bun ios` is the lighter app-start command.
- Use `bun macos` for the native macOS app; the old Electron flow is obsolete.
- When adding schema changes, keep the order `db:generate` -> review migration -> `db:migrate` or `db:push` as appropriate.
- Keep progress docs current: add a `changelog/entries/unreleased/` entry in the same commit, file remaining work in `backlog/` or `user-tasks/`, and update `PRD.md` / `APPS_ARCHITECTURE.md` when scope or the app surface changes. See [AGENT_CONTEXT.md §10](AGENT_CONTEXT.md#10-documentation-map) for the full doc map.

---

## Backend Architecture (`apps/server`)

- **Runtime:** Cloudflare Worker
- **HTTP framework:** Hono (`src/main.ts` entry point)
- **API layer:** tRPC router at `src/trpc/index.ts`, per-domain routers in `src/trpc/routes/`
- **Database:** PostgreSQL via Drizzle ORM + Cloudflare Hyperdrive. Schema: `src/db/schema.ts`
- **Auth:** Better Auth (`src/lib/auth.ts`) — Google OAuth, Apple Sign In, Email OTP, Bearer plugin, JWT plugin
- **Durable Objects:** ZeroDriver, ZeroAgent, ZeroDB, ZeroMCP, ShardRegistry, WorkflowRunner, ThreadSyncWorker
- **Infrastructure:** KV namespaces, Queues, Workflows for async email sync
- **Deploy:** `bun deploy:backend` → Wrangler (`wrangler.jsonc`)
- **Dev utilities:** `bun test:ai`, `bun eval`, `bun eval:dev`, `bun eval:ci`

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
- **Build/deploy:** `bun run --filter=@zero/web build` and `bun run --filter=@zero/web deploy` (the root `build:frontend` / `deploy:frontend` scripts still target the legacy `apps/mail` archive)

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
- **Build commands:** `bun ios`, `bun ios:simulator`, `bun ios:build:preview`, `bun ios:build:production`

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
| `changelog/` | Change log — one entry file per item, written in the same commit (`CHANGELOG.md` is a pointer stub) |
| `backlog/` | Code follow-ups + deferred fixes (`TASK.md` / `CODE_REVIEW_BACKLOG.md` are pointer stubs) |
| `user-tasks/` | Work only the repo owner can do, outside the codebase |
| `docs/agent-memory/` | Durable gotchas, `active-work.md` file claims, `regressions.md` |
| `SELF_HOSTING.md`, `SECURITY.md`, `MCP.md`, `SCRIPTS_GUIDE.md` | Operational guides |
| `PLANNING.md` / `ROADMAP.md` | Historical migration + roadmap snapshots |

See [AGENT_CONTEXT.md §10](AGENT_CONTEXT.md#10-documentation-map) for the full doc map (active vs historical).

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

# Agent Context — Todus

> **Read this first.** Single source of truth for any AI agent (Claude, Cursor, Codex, Gemini, Copilot) working in this repo. Last updated: 2026-05-27.
>
> If anything here contradicts another `.md` file, **this file wins** until that file is updated. See [Documentation Map](#documentation-map) for the catalog of every doc and what it's for.

---

## 1. What is Todus?

**Todus** is a unified productivity app — email, calendar, tasks, docs, meetings, and an AI assistant — built around one shared data model and a single backend.

- Web: `todus.app` (production)
- iOS: native SwiftUI app (Bundle ID `com.ludvighedin.todus`)
- macOS: native SwiftUI app (DMG distributed via Cloudflare R2)
- Android: scaffolded only (Expo `pnpm android`); not actively shipped
- Backend: single Cloudflare Worker (`todus-server-v1`)

It is NOT three separate apps stitched together. Email threads, calendar events, tasks, and docs share the same Postgres model and the same tRPC API. The AI assistant operates across all of them via tool calls.

---

## 2. Repo layout — the 90 % you need

```
mail/                                  ← monorepo root (pnpm + Turborepo)
├── apps/
│   ├── web/                           ← ACTIVE frontend (React Router v7 + Vite + CF Workers)
│   ├── mail/                          ← LEGACY frontend — READ-ONLY ARCHIVE, do not edit
│   ├── server/                        ← Backend Cloudflare Worker (Hono + tRPC + Drizzle + DOs)
│   ├── ios/Todus/                     ← Native iOS app (Swift 6, SwiftUI, iOS 18+)
│   ├── macos/TodusMac/                ← Native macOS app (Swift 6, SwiftUI, macOS 15+)
│   └── archived/                      ← Old RN / Electron / SwiftUI-WebView code. Reference only.
├── packages/
│   ├── shared/                        ← Types + utils shared web ↔ server
│   ├── api-client/                    ← HTTP client for tRPC
│   ├── design-tokens/                 ← Cross-platform design constants
│   ├── ui-native/                     ← Shared RN components (legacy holdover)
│   ├── macos-doc-editor/              ← Tiptap editor bundle used by macOS doc view
│   ├── swift-auth/                    ← SPM package: shared iOS/macOS auth utilities
│   ├── swift-widgets/                 ← SPM package: shared iOS/macOS widget extensions
│   ├── cli/                           ← `nizzy` CLI (workspace sync, runs as postinstall)
│   ├── testing/                       ← Vitest test suite
│   ├── tsconfig/                      ← Shared tsconfig presets
│   └── eslint-config/                 ← Shared ESLint config
├── scripts/                           ← Build/parity/release scripts (tsx + bash + node)
├── parity_screenshots/                ← Visual regression baselines (manifest + PNGs)
├── docs/                              ← Long-form design specs, plans, ADRs
└── *.md                               ← Root-level docs (see §10 Documentation Map)
```

### The `apps/web` vs `apps/mail` split — read this carefully

There are **two** React Router v7 apps in the repo. This trips up every new agent.

| | `apps/web` | `apps/mail` |
|---|---|---|
| Status | **Active** — all current frontend work | **READ-ONLY archive** — do not edit |
| pnpm filter | `@zero/web` | `@zero/mail` |
| `pnpm dev` / `pnpm web` | ✅ runs this | ❌ |
| `pnpm mail` | ❌ | ✅ runs this (for reference only) |
| `pnpm build:frontend` | ❌ | ⚠️ **still builds `@zero/mail`** (stale script — see below) |
| `pnpm deploy:frontend` | ❌ | ⚠️ **still deploys `@zero/mail`** (stale script — see below) |
| Routes | Marketing + auth + `/mail/*` product + `/settings/*` + `/blog/*` etc. | Mail product only |

**⚠️ Known inconsistency:** `pnpm build:frontend` and `pnpm deploy:frontend` in root `package.json` still target `@zero/mail`. Both wrangler configs deploy to the same Cloudflare Worker name (`todus`), so the result depends on which one was deployed last. When you actually need to ship `apps/web` to production, run `pnpm --filter=@zero/web build && pnpm --filter=@zero/web deploy` directly until those scripts are fixed.

**For agents: only edit files under `apps/web/`. Never edit anything under `apps/mail/`.**

---

## 3. Tech stack snapshot

| Layer | Tech | Where |
|---|---|---|
| Web framework | React Router v7 — client-rendered SPA (`ssr: false`) + build-time prerendered marketing pages, on Vite + Cloudflare Workers | `apps/web` |
| Web styling | Tailwind CSS v4 (CSS-first config via `@theme` in `globals.css`) + shadcn/ui | `apps/web/app/globals.css`, `apps/web/components/ui/` |
| Web state | Jotai atoms + TanStack Query | `apps/web/app/` |
| Rich text | Tiptap (also bundled for macOS) | `packages/macos-doc-editor` |
| i18n | Paraglide JS | `apps/web/messages/` → compiled `paraglide/` |
| Backend HTTP | Hono on Cloudflare Workers | `apps/server/src/main.ts` |
| API layer | tRPC v11 + Superjson | `apps/server/src/trpc/` |
| Database | PostgreSQL via Drizzle ORM + Cloudflare Hyperdrive | `apps/server/src/db/schema.ts` |
| Auth | Better Auth (Google / Apple / Email OTP / phone) | `apps/server/src/lib/auth.ts` |
| AI | OpenRouter + Anthropic + local MLX (iOS/macOS) | `apps/server/src/services/`, `apps/ios|macos/.../Services/AI/` |
| iOS | Swift 6 / SwiftUI / SwiftData / EventKit / MLX | `apps/ios/Todus/Todus/` |
| macOS | Swift 6 / SwiftUI / EventKit / MLX | `apps/macos/TodusMac/` |
| Infrastructure | Cloudflare (Workers + KV + R2 + Hyperdrive + Queues + Workflows) | `apps/server/wrangler.jsonc` |

---

## 4. Where things live — feature map

### Web (`apps/web/app/`)

```
(auth)/todus/login/page.tsx              ← /login
(auth)/todus/signup/page.tsx             ← /signup
(full-width)/                            ← Marketing pages
  about.tsx, terms.tsx, pricing.tsx, privacy.tsx, contact.tsx,
  faq.tsx, hr.tsx, downloads.tsx, blog/, compare/, share/, group-join/
(routes)/
  mail/                                  ← The actual mail product
    page.tsx (inbox), [folder]/, compose/, search/, create/,
    home/, tasks/, calendar/, meetings/, docs/, under-construction/
  settings/                              ← All settings surfaces
    general, appearance, ai, billing, calendars, categories,
    connections, danger-zone, design-system, labels, local-models,
    meetings, notifications, privacy, security, sharing,
    shortcuts, signatures, [...settings]
  developer/                             ← /developer
home/                                    ← Landing-page hero content
components/                              ← Shared UI (shadcn-derived)
globals.css                              ← Design tokens (single source of truth for web)
routes.ts                                ← React Router route config
```

### Backend (`apps/server/src/`)

```
main.ts                                  ← Hono entry, all routes, mobile-token handoff
env.ts                                   ← Typed Cloudflare env binding
types.ts, ctx.ts                         ← Shared types + tRPC context
pipelines.ts, pipelines.effect.ts        ← Sync pipelines
db/schema.ts                             ← Drizzle Postgres schema
lib/
  auth.ts                                ← Better Auth config (providers, trustedOrigins)
  schemas.ts                             ← Zod schemas (userSettings, etc.)
services/                                ← Email/AI/calendar service logic
trpc/
  index.ts                               ← Router composition
  routes/                                ← One file per domain (see §5)
workflows/                               ← Cloudflare Workflow handlers
thread-workflow-utils/                   ← Helpers for the sync workflow
```

### iOS (`apps/ios/Todus/Todus/`)

```
App/                                     ← TodosApp.swift (@main), AppServices (DI), RootView
Navigation/                              ← MainTabView, CustomTabBar, CreateSheet
Features/
  Home/        AI/        Auth/         Calendar/     Docs/
  Email/       Tasks/     Meetings/     Notifications/ Search/
  Folders/     Voice/     Settings/     DesignSystem/  MoreSheetView.swift
Services/
  Auth/      API/       Email/      AI/       Calendar/
  Tasks/     Reminders/ Parsing/    Docs/     Drafts/
  Meetings/  Voice/     Subscription/ Notifications/ Widgets/
  AppLogger.swift, NetworkMonitor.swift
Domain/      ← DTOs, enums (TaskStatus, AppTaskPriority, EmailModels, …)
Data/        ← SwiftData models (TaskRecord, FolderRecord) + AppConfiguration
DesignSystem/← AppTheme.swift (tokens), BrandIcons, Formatters
Resources/   ← Assets.xcassets, Info.plist
```

### macOS (`apps/macos/TodusMac/`)

```
App/         ← TodusMacApp.swift (@main), MacAppServices, MacRootView
Views/
  Home/      AI/         Calendar/     Create/     Docs/
  Email/     Folders/    Meetings/     Notifications/ Search/
  Settings/  Tasks/      Voice/
Services/    ← Same shape as iOS Services/ — AI, API, Auth, Email, …
Domain/      ← Mirror of iOS Domain/
Data/        ← Mirror of iOS Data/
DesignSystem/← MacTheme.swift (tokens), MacScrollStyle, …
MacMeetingsView.swift, MacMeetingDetailView.swift, MeetingsService.swift (top-level holdovers)
```

iOS and macOS Services/ folders deliberately mirror each other so logic ports cleanly.

---

## 5. tRPC routes (current, from `apps/server/src/trpc/routes/`)

Router **files** (`apps/server/src/trpc/routes/*.ts`): `ai`, `assistant`, `avatar`, `bimi`, `brain`, `calendar`, `categories`, `connections`, `contact`, `cookies`, `docs`, `drafts`, `groups`, `label`, `logging`, `mail`, `mail-assistant`, `meet`, `mentions`, `notes`, `sessions`, `settings`, `sharing`, `shortcut`, `subscription`, `tasks`, `templates`, `user`.

⚠️ **The client mount key differs from the file name for a few** — call these on the client, not the file name: `cookies.ts` → `cookiePreferences`, `label.ts` → `labels`, `mail-assistant.ts` → `mailAssistant`, and `tasks.ts` exports **two** routers → `tasks` **and** `folders`. Full mount-key catalog: [docs/api.md](docs/api.md).

When adding a new domain: create `apps/server/src/trpc/routes/<name>.ts`, register it in `apps/server/src/trpc/index.ts`, then call it from the client.

---

## 6. Auth — the one bit everyone gets wrong

- **Library:** Better Auth (`apps/server/src/lib/auth.ts`)
- **Providers enabled:** Google OAuth, Apple Sign In, Email OTP (via Resend), phone number (via Twilio), email/password (verification required). Microsoft is commented out.
- **Web client:** `apps/web/lib/auth-client.ts` (NOT `apps/mail/...` — that path is the legacy archive)
- **iOS client:** `apps/ios/Todus/Todus/Services/Auth/AuthService.swift`
- **macOS client:** `apps/macos/TodusMac/Services/Auth/AuthService.swift`
- **Production domain:** `todus.app`; `COOKIE_DOMAIN=todus.app` in `apps/server/wrangler.jsonc`
- **Trusted origins:** hardcoded in `createAuthConfig()` — update when adding new origins.

### Native auth flow (iOS / macOS)

1. **Apple Sign In:** native `ASAuthorizationAppleIDProvider` → ID token → `POST /api/auth/sign-in/social` `{ provider: "apple", idToken }` → Bearer token returned → stored in Keychain.
2. **Google Sign In:** `ASWebAuthenticationSession` opens backend Google OAuth → backend redirects to `/api/auth/mobile-token` → server creates a **dedicated native session row** (separate from web OAuth session) → server issues a JWT + refresh token → deep links to `todus://auth-callback?token=<jwt>&refreshToken=<refresh>&sessionId=<id>` → stored in Keychain.
3. **Email OTP:** `POST /api/auth/email-otp/send-verification-otp` → Resend delivers 6-digit code → user enters code → `POST /api/auth/email-otp/verify-email` → Bearer token → Keychain.

**Don't use WKWebView fetch for cross-origin API calls** — use native `URLSession`. `loadHTMLString` always gives a `null` security origin; relative URL resolution still works but `fetch` will fail CORS.

### Bearer-token API calls

All native API calls go through `TodosAPIClient` (iOS) / `MacTodosAPIClient` (macOS):

- `POST /api/trpc/<procedure>` with Superjson-wrapped body
- `Authorization: Bearer <token>` header
- Automatic JWT refresh using the stored refresh token

---

## 7. Design system

Single canonical reference: [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md). Drift tracker: [DESIGN_SYSTEM_INCONSISTENCIES.md](DESIGN_SYSTEM_INCONSISTENCIES.md).

**Sources of truth:**

| Platform | File |
|---|---|
| Web | `apps/web/app/globals.css` |
| iOS | `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift` |
| macOS | `apps/macos/TodusMac/DesignSystem/MacTheme.swift` |

**Live in-app viewers** (gated to `TODUS_ALLOWLISTED_EMAILS` / `VITE_TODUS_ALLOWLISTED_EMAILS`):
- Web: `/settings/design-system`
- iOS: Settings → Developer → Design System
- macOS: Settings → Developer → Design System

**Allowlist mechanism:**
- Swift: `packages/swift-auth/Sources/TodusAuth/TodusDeveloperAccess.swift::TodusDeveloperAccess.isAllowlisted(email:)`
- Web: `apps/web/lib/developer-access.ts::isAllowlisted(email)`

**Rules**:
- Always prefer semantic tokens (`Motion.fast / base / slow`, `--space-*`, `--surface-*`) over inline values (`.snappy(...)`, `duration-150`, hex colors).
- Canonical dark background is Apple system dark `#1c1c1e` (`Color(white: 0.109)`).
- Whenever you add or change a token, update **all three** sources + [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) in the same change.

Current cross-platform spacing scale (mirrors iOS/macOS):

| Token | px |
|---|---|
| `xs` | 4 |
| `sm` | 8 |
| `md` | 12 |
| `lg` | 16 |
| `xl` | 24 |
| `2xl` | 32 |

---

## 8. Commands you'll actually run

```bash
# Daily dev
pnpm go                         # docker DB + apps/web + backend (full stack)
pnpm dev                        # apps/web + backend (DB already running)
pnpm web                        # alias for pnpm dev
pnpm ios                        # open iOS Xcode project (lightest)
pnpm ios:simulator              # build + boot iOS simulator
pnpm macos                      # run native macOS app

# Database (Drizzle)
pnpm db:generate                # generate migration from schema diff
pnpm db:migrate                 # apply pending migrations
pnpm db:push                    # push schema directly (dev)
pnpm db:studio                  # Drizzle Studio GUI

# Build + deploy
pnpm build                                      # turbo build all
pnpm --filter=@zero/web build                   # build apps/web specifically
pnpm --filter=@zero/web deploy                  # deploy apps/web (preferred)
pnpm deploy:backend                             # deploy apps/server
pnpm ios:build:preview                          # iOS preview .ipa
pnpm ios:build:production                       # iOS App Store / TestFlight .ipa
./scripts/build-mac-dmg.sh                      # macOS DMG (archives, signs, uploads to R2)

# Parity screenshots
pnpm parity:screenshots:check                   # presence check across web/ios/macos
pnpm parity:screenshots:capture:web             # Playwright web capture
pnpm parity:screenshots:capture:ios             # interactive iOS sim capture
pnpm parity:screenshots:capture:ios:auto        # deeplink-driven (no interaction)
pnpm parity:screenshots:capture:macos:auto      # native macOS app capture
pnpm parity:screenshots:capture:android:auto    # Android emulator capture

# AI evals / tests
pnpm test                       # run vitest suite in packages/testing
pnpm test:ai                    # backend AI tests
pnpm eval                       # run backend AI evals
pnpm eval:ci                    # CI-mode evals
```

**Never run `pnpm check`, `pnpm lint`, or `pnpm format` project-wide** — they sweep the whole monorepo. Lint/format only the files you touched (e.g. `npx eslint apps/web/components/foo.tsx`, `npx prettier --write apps/server/src/lib/schemas.ts`).

---

## 9. Environment variables (high-impact only)

Backend (`apps/server/wrangler.jsonc` `vars` and Cloudflare secrets):
- `BETTER_AUTH_SECRET` (secret) — required
- `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` — required for Google sign-in
- `APPLE_*` — for Apple Sign In
- `RESEND_API_KEY` — for email OTP
- `TWILIO_*` — for phone OTP
- `OPENROUTER_API_SECRET` — for AI (fallback: `OPENROUTER_API_KEY`)
- `ANTHROPIC_API_KEY` — for AI
- `COOKIE_DOMAIN` — `todus.app` in production
- `HYPERDRIVE` (binding) — Postgres proxy
- `TODUS_ALLOWLISTED_EMAILS` — comma-separated list for gated features

Frontend (`apps/web/.env` or Cloudflare env, prefix `VITE_PUBLIC_*`):
- `VITE_PUBLIC_BACKEND_URL`
- `VITE_PUBLIC_APP_URL`
- `VITE_TODUS_ALLOWLISTED_EMAILS`

iOS / macOS: most env config lives in `Info.plist`; the bearer token lives in the Keychain; allowlisted emails are bundled at build time via `TODUS_ALLOWLISTED_EMAILS`.

---

## 10. Documentation Map

Every `.md` file in the root, what it's for, and whether to trust it:

### Trust these — kept current

| File | Purpose |
|---|---|
| `AGENT_CONTEXT.md` | **This file.** First read for every agent. |
| `CLAUDE.md` | Claude Code–specific guidance (mirrors this file with a Claude angle). |
| `AGENTS.md` | Agent-agnostic architecture reference (mirrors this file). |
| `APPS_ARCHITECTURE.md` | Canonical runtime-target map (iOS / Web / Backend / macOS). |
| `FEATURES.md` | Per-surface feature catalog with clickable file paths. |
| `FEATURE_TEST_PLAN.md` | Companion to `FEATURES.md` — per-feature test checklists. |
| `DESIGN_SYSTEM.md` | Canonical design tokens across all three platforms. |
| `DESIGN_SYSTEM_INCONSISTENCIES.md` | Drift tracker for resolved + open cross-platform mismatches. |
| `CHANGELOG.md` | Running log of significant changes. Append to `[Unreleased]`. |
| `TASK.md` | Sprint-level task tracking. Currently focused on iOS hardening + parity. |
| `CODE_REVIEW_BACKLOG.md` | Deferred fixes flagged during bug hunts / reviews. |
| `PRD.md` | Product requirements: user flows, screens, empty states, notifications. |
| `SELF_HOSTING.md` | Self-hosting setup guide (prereqs, env vars, OAuth setup). |
| `SECURITY.md` | Secret handling, vulnerability reporting. |
| `MCP.md` | Todus's exposed MCP surface (email/label/drafts/calendar/AI). |
| `SCRIPTS_GUIDE.md` | Pnpm script catalog. |
| `README.md` | Public-facing overview. |
| `parity_screenshots/SCREENSHOT_LOG.md` | Visual regression log. |

### Historical / niche — read only if asked

| File | Note |
|---|---|
| `PROJECT_PLAN.md` | Historical. Describes Expo-WebView iOS + Electron macOS — both replaced by native SwiftUI. Kept for context, do not act on. |
| `PLANNING.md` | Historical migration plan (RN-shell → native). Mostly executed. |
| `ROADMAP.md` | High-level product wishlist. |
| `GEMINI.md` | Project context for Gemini CLI. Re-synced 2026-05-27. |
| `TESTFLIGHT_*` / `GETTING_TO_TESTFLIGHT.md` / `README_TESTFLIGHT.md` | iOS TestFlight playbooks. |
| `APP_BUILD_STATUS.md` / `APPS_NATIVE_MIGRATION.md` / `APPS_STRUCTURE.md` | Migration-era snapshots. |
| `CLAUDE_PARITY_CHECKLIST.md` / `CODEX_PARITY_CHECKLIST.md` / `PARITY_CHECKLIST.md` | Agent-specific parity audits. |
| `STRIPE_SUBSCRIPTION_STATUS.md` | Billing integration status. |
| `RESTRUCTURING_SUMMARY.md` / `DEPLOYMENT_SESSION_SUMMARY.md` | Session snapshots. |
| `MANUAL_INPUTS_GUIDE.md` / `WORKING_APP_CHECKLIST.md` / `UX_ISSUES.md` / `SEO-AUDIT.md` | Spot-purpose docs. |
| `auth_macos_gap_analysis.md` / `auth_macos_plan.md` | Plan/audit for macOS auth migration. |
| `goal.md` / `plan.md` / `ALL_TERMINAL_COMMANDS.md` / `CLAUDE_TEMP_INPUT.md` | Scratch notes — likely stale. |

### Long-form

| Path | Note |
|---|---|
| `docs/superpowers/specs/` | Approved design specs per feature. |
| `docs/superpowers/plans/` | Implementation plans (post-approval). |
| `docs/*.md` (architecture, backend, frontend, database, api, deployment, mcp, agents) | Code-derived technical reference set (added 2026-06-13). Start at [docs/README.md](docs/README.md). |

---

## 11. Recent shipped work (last ~14 days)

For an authoritative log, read `CHANGELOG.md`. High-impact items so the next agent has context:

- **macOS DMG distribution** wired end to end — `scripts/build-mac-dmg.sh` archives + signs + uploads to Cloudflare R2; `/downloads` page serves the DMG.
- **Local MLX inference (iOS + macOS)** — `mlx-swift-examples` SPM dependency wired into both Xcode targets. Settings → Local Models now scans both the in-app HF cache and the user's `~/.cache/huggingface/hub`. New `HuggingFaceCacheConnector` on macOS surfaces externally-pulled `mlx-community/*` models.
- **Native auth session separation** — Google OAuth deep-link flow now creates a dedicated `session` row for the native app so "Active Sessions" reflects iOS/macOS independently from web.
- **Settings sync expansion** — `aiTone`, `taskRemindersEnabled`, `calendarRemindersEnabled` moved from `@AppStorage`-only to backend-synced (`apps/server/src/lib/schemas.ts::userSettingsSchema`).
- **Web design system overhaul** — explicit `--space-*` scale, `--surface-primary/secondary/sheet` aliases, `--motion-duration-base` 220→250 ms, `--motion-duration-slow` 320→350 ms.
- **Docs feature overhaul** — iOS + macOS native shells around Tiptap, autosave parity, persistent saved badge, four review-pass round of UX polish.
- **iOS compose** — From picker, gray placeholders, heavier scrim in CreateSheet.
- **iOS email** — folder switch, HTML overflow, thread prefetch, header alignment fixes.
- **iOS AI** — blue send button, tap-to-dismiss keyboard, context pill on user bubbles.
- **Contrast fix** — no more white-on-white buttons in dark mode (iOS + macOS).

---

## 12. Working rules for agents

1. **Verify, don't assume.** If you're unsure whether a file/path/symbol exists, read it.
2. **No project-wide lint/format runs.** Only touch what you change.
3. **No new git branches** unless the user asks. Commit on the existing branch.
4. **Never edit `apps/mail/`** — archive only. All frontend changes go in `apps/web/`.
5. **Never edit `apps/archived/`** — reference only.
6. **Update the relevant doc when you change behavior** — `CHANGELOG.md`, and one of `TASK.md` / `PLANNING.md` / `PRD.md` / `APPS_ARCHITECTURE.md` depending on scope.
7. **Design system tokens** — update web + iOS + macOS sources + `DESIGN_SYSTEM.md` together. Never one in isolation.
8. **Native API calls** use `URLSession`, never `WKWebView` fetch.
9. **For cross-platform features**, mirror Services/ folder layout: iOS and macOS Services/ should keep matching names and shapes.
10. **Schema changes** flow `db:generate` → review migration → `db:migrate` or `db:push` (dev).

When in doubt, ask. Don't guess.

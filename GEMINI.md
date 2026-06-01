# Todus Project Context (Gemini)

> Last updated: 2026-05-27. This file is the Gemini-CLI mirror of [AGENT_CONTEXT.md](AGENT_CONTEXT.md). When in doubt, read AGENT_CONTEXT.md first — it is the canonical source.

## Project Overview

**Todus** is a unified productivity app — email, calendar, tasks, docs, meetings, and an AI assistant — sharing one data model and one Cloudflare Workers backend. It is shipped on web, iOS, and macOS.

### Architecture

Todus is a **pnpm + Turborepo** monorepo.

- **Apps (`apps/`)**:
  - `web`: **Active frontend.** React Router v7 + Vite + Cloudflare Workers + Tailwind CSS v4 + shadcn/ui. Serves marketing, auth, `/mail/*` product, `/settings/*`, `/developer`.
  - `mail`: **Legacy frontend, READ-ONLY archive.** Superseded by `apps/web`. Do not edit.
  - `server`: Cloudflare Worker (Hono + tRPC + Drizzle ORM + PostgreSQL via Hyperdrive + Durable Objects + Workflows).
  - `ios/Todus`: Native iOS app — Swift 6, SwiftUI, iOS 18+. Bundle ID `com.ludvighedin.todus`.
  - `macos/TodusMac`: Native macOS app — Swift 6, SwiftUI, macOS 15+. DMG via Cloudflare R2.
  - `archived/*`: Reference-only legacy (RN-CLI / Electron / SwiftUI-WebView). Do not use.

- **Packages (`packages/`)**:
  - `shared`, `api-client`, `design-tokens`, `ui-native`, `macos-doc-editor`, `cli` (nizzy), `swift-auth` (SPM), `swift-widgets` (SPM), `testing` (vitest), `tsconfig`, `eslint-config`.

### Core Technologies

- **Frontend (web):** React Router v7, Vite, Cloudflare Workers SSR, Tailwind CSS v4, shadcn/ui-derived components, Jotai, TanStack Query, Tiptap, Paraglide JS i18n.
- **Backend:** Hono, tRPC v11, Better Auth (Google / Apple / Email OTP / phone / email+password), Drizzle ORM, Cloudflare Hyperdrive Postgres, Durable Objects, Cloudflare Workflows, KV, Queues, R2.
- **iOS / macOS:** Swift 6 strict concurrency, SwiftUI, SwiftData, EventKit, MLX-Swift for local AI (`mlx-swift-examples`).
- **Database:** PostgreSQL via Drizzle ORM. Local dev runs PostgreSQL in Docker.
- **Tooling:** pnpm workspaces, Turborepo, TypeScript strict mode, Prettier, ESLint / oxlint.

---

## Building and Running

### Prerequisites
- Node.js v18+
- pnpm v10+
- Docker v20+

### Setup
```bash
pnpm install
pnpm nizzy env && pnpm nizzy sync
pnpm docker:db:up
pnpm db:push
```

### Daily dev
```bash
pnpm go                  # docker DB + apps/web + backend
pnpm dev                 # apps/web + backend (DB already running)
pnpm ios                 # open iOS Xcode project
pnpm ios:simulator       # build + boot iOS simulator
pnpm macos               # run native macOS app
```

### Build + deploy
```bash
pnpm --filter=@zero/web build           # build active frontend
pnpm --filter=@zero/web deploy          # deploy active frontend (preferred)
pnpm deploy:backend                     # deploy server
pnpm ios:build:preview / ios:build:production
./scripts/build-mac-dmg.sh              # signed macOS DMG → R2
```

⚠️ `pnpm build:frontend` / `pnpm deploy:frontend` in root `package.json` still target the **legacy** `apps/mail` archive. Always use `--filter=@zero/web` to ship the active frontend.

### Database
```bash
pnpm db:generate / db:migrate / db:push / db:studio
```

---

## Working rules

- **Never edit `apps/mail/`** — read-only archive.
- **Never edit `apps/archived/`** — reference only.
- **Never run `pnpm check` / `pnpm lint` / `pnpm format` project-wide** — they sweep the entire monorepo. Lint/format only files you touched.
- **Never create git branches** unless explicitly asked.
- **Update the design system in all three sources together** — `apps/web/app/globals.css`, `apps/ios/.../AppTheme.swift`, `apps/macos/.../MacTheme.swift`, plus `DESIGN_SYSTEM.md`.
- **Native API calls use `URLSession`** — never `WKWebView` fetch (the security origin is `null` for `loadHTMLString`).
- See [AGENT_CONTEXT.md §12](AGENT_CONTEXT.md#12-working-rules-for-agents) for the full ruleset.

---

## Development Conventions

- **Monorepo workflow:** use `pnpm` and respect workspace boundaries (`pnpm-workspace.yaml`). Add dependencies with `--filter`.
- **Typing:** strict TypeScript. Configs shared from `packages/tsconfig`.
- **Styling:** Tailwind CSS v4 (CSS-first `@theme` directive). Cross-platform tokens in `packages/design-tokens` and the three platform source files.
- **Formatting / linting:** Prettier + oxlint + ESLint. File-scoped only.
- **Database migrations:** `pnpm db:generate` → review SQL → `pnpm db:migrate` or `pnpm db:push`.
- **External integrations:** Gmail API (Google OAuth scopes `gmail.modify` + `gmail.readonly` + `gmail.send`), Resend (email OTP), Twilio (phone OTP), Apple Sign In, OpenRouter + Anthropic + local MLX for AI.

---

## Key docs

- `AGENT_CONTEXT.md` — canonical agent reference (start here)
- `CLAUDE.md` — Claude-specific delta
- `AGENTS.md` — agent-agnostic mirror
- `APPS_ARCHITECTURE.md` — runtime target map
- `DESIGN_SYSTEM.md` + `DESIGN_SYSTEM_INCONSISTENCIES.md` — tokens + drift
- `PRD.md` — product requirements (user flows, screens)
- `CHANGELOG.md` — append to `[Unreleased]`
- `SELF_HOSTING.md`, `SECURITY.md`, `MCP.md`, `SCRIPTS_GUIDE.md` — operational

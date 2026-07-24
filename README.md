<p align="center">
  <picture>
    <source srcset="apps/web/public/brand-logo.svg" media="(prefers-color-scheme: dark)">
    <img src="apps/web/public/brand-logo.svg" alt="Todus Logo" width="64" />
  </picture>
</p>

# Todus

The AI-native email client that manages your inbox, calendar, and tasks — so you don't have to.

Todus runs on the web, macOS, and iOS, with a Cloudflare Workers backend. The frontend lives in `apps/web`, the backend in `apps/server`, and native clients under `apps/ios` and `apps/macos`.

## Features

- **AI email triage** — summarize, draft, and auto-categorize incoming mail.
- **Unified inbox** — Gmail today, Outlook in development.
- **Calendar + tasks** — combined view alongside email.
- **Multi-platform** — web, iOS, and macOS clients share the same backend.
- **Open source** — self-host or contribute.

## Download

- macOS, iPhone, and the web app: [todus.app/downloads](https://todus.app/downloads)

## Tech Stack

- **Frontend (web)**: React Router v7, Vite, Tailwind CSS v4, deployed on Cloudflare Workers
- **Backend**: Cloudflare Workers (Hono + tRPC + Durable Objects + Workflows)
- **Database**: PostgreSQL via Drizzle ORM + Cloudflare Hyperdrive
- **Authentication**: Better Auth (Google, Apple, Email OTP)
- **iOS**: Swift 6 / SwiftUI
- **macOS**: Swift 6 / SwiftUI

See [APPS_ARCHITECTURE.md](APPS_ARCHITECTURE.md) for the canonical app surface.

## Self-Hosting

See [SELF_HOSTING.md](SELF_HOSTING.md) for the full setup guide: prerequisites, environment variables, OAuth setup, and database commands.

Quick start:

```bash
git clone https://github.com/Ludvig-Hedin/Todus.git
cd Todus
bun install
bun docker:db:up
bun nizzy env && bun nizzy sync
bun db:push
bun dev
```

Visit [http://localhost:3000](http://localhost:3000).

## Documentation

- **[AGENT_CONTEXT.md](AGENT_CONTEXT.md)** — canonical reference for contributors and AI agents (repo map, feature index, working rules).
- **[docs/](docs/README.md)** — code-derived technical reference: [architecture](docs/architecture.md), [backend](docs/backend.md), [frontend](docs/frontend.md), [database](docs/database.md), [API](docs/api.md), [deployment](docs/deployment.md), [MCP](docs/mcp.md).
- **[APPS_ARCHITECTURE.md](APPS_ARCHITECTURE.md)** · **[DESIGN_SYSTEM.md](DESIGN_SYSTEM.md)** · **[SELF_HOSTING.md](SELF_HOSTING.md)** · **[SECURITY.md](SECURITY.md)**

## Contribute

See the [contributing guide](.github/CONTRIBUTING.md) and the [translation guide](.github/TRANSLATION.md).

## Powered by

<div style="display: flex; justify-content: center;">
  <a href="https://vercel.com" style="text-decoration: none;">
    <img src="public/vercel.png" alt="Vercel" width="96"/>
  </a>
  <a href="https://better-auth.com" style="text-decoration: none;">
    <img src="public/better-auth.png" alt="Better Auth" width="96"/>
  </a>
  <a href="https://orm.drizzle.team" style="text-decoration: none;">
    <img src="public/drizzle-orm.png" alt="Drizzle ORM" width="96"/>
  </a>
  <a href="https://coderabbit.com" style="text-decoration: none;">
    <img src="public/coderabbit.png" alt="Coderabbit AI" width="96"/>
  </a>
</div>

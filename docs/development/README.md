# Development Documentation

This folder contains guides for local development setup, configuration, and development workflows.

## 📚 Documents

### SCRIPTS_GUIDE.md
Reference guide for all npm scripts and commands:
- Active app commands (iOS, macOS, Web, Backend)
- Database commands
- Build and deployment commands
- Code quality tools
- Development shortcuts

**Use this**: When you need to know what command to run

## 🎯 Quick Commands

### Getting Started
```bash
pnpm install          # Install dependencies
pnpm nizzy env        # Setup environment
pnpm nizzy sync       # Sync environment variables
pnpm docker:db:up     # Start database
pnpm db:push          # Initialize database
pnpm dev              # Start development
```

### Development
```bash
pnpm go               # Quick start (everything in one command)
pnpm ios              # Run iOS simulator
pnpm macos            # Run macOS app
pnpm dev              # Run web + backend
```

### Database
```bash
pnpm db:push          # Push schema changes
pnpm db:generate      # Generate migrations
pnpm db:migrate       # Apply migrations
pnpm db:studio        # Open Drizzle Studio (visual DB editor)
```

**`PostgresError: role "postgres" does not exist` (local macOS):** Docker and many tutorials use the database user `postgres`. Homebrew’s PostgreSQL often does **not** create that user; the default superuser is usually your **macOS account short name** (`whoami`).

- **Quickest fix:** in `.env`, set `DATABASE_URL` to that user, for example:
  - `postgresql://yourname@localhost:5432/todus` (no password), or
  - `postgresql://yourname:yourpassword@localhost:5432/todus` if you use one.
- **Ensure the database exists:** `createdb todus` (or `CREATE DATABASE todus;` in `psql`).
- **If you want the sample URL as-is** (`postgres:postgres@...`): from `psql` as a superuser, run
  `CREATE ROLE postgres WITH LOGIN SUPERUSER PASSWORD 'postgres';`
  (then keep `DATABASE_URL` matching that user and password).

Production / hosted Postgres almost always has a user defined in the host’s dashboard; point `DATABASE_URL` there, then run `pnpm db:migrate` (or your host’s migration flow).

**Production migrations:** Prefer **`migrate`** over **`db:push`**. From the repo root, with a production URL (usually `?sslmode=require` or your provider’s required params):

```bash
# Avoid putting secrets on the command line (shell history, process listings). Export for this session only:
export DATABASE_URL='postgresql://…'
pnpm run -C apps/server db:migrate
unset DATABASE_URL
```

Prefer loading the URL from a password manager or your host’s CLI, and clear it from the shell after the run when practical.

**Important:** Migrations run against **whichever database `DATABASE_URL` points to**. A successful `pnpm db:migrate` using your **local** `.env` only updates **localhost** (or whatever is in that file). Native and web clients hitting **`https://api.todus.app`** use **production** Postgres. Errors like “missing doc tables” / HTTP **412** on `docs.*` there mean production has not received the migrations—you must run the command above with the **`DATABASE_URL` from your API host’s secrets** (same one the worker uses), not `localhost`.

**Production (Cloudflare Workers + Hyperdrive):** The Worker does not run `drizzle-kit` at deploy time. The **origin** connection string is configured on the [Hyperdrive](https://developers.cloudflare.com/hyperdrive/) config in the Cloudflare dashboard (see `HYPERDRIVE` in `apps/server/wrangler.jsonc`). Use that same **direct Postgres URL** (Neon/RDS, etc. — with `?sslmode=require` if required) for migrations.

**Automated production migrations (recommended):** Workflow **db-migrate-production** (`.github/workflows/db-migrate-production.yml`) runs `pnpm run -C apps/server db:migrate` using the repository secret **`PRODUCTION_DATABASE_URL`**. Add that secret in **GitHub → Settings → Secrets and variables → Actions** (same **direct Postgres URL** the Cloudflare Hyperdrive **origin** uses — the database server, not the Workers binding; see `HYPERDRIVE` in `apps/server/wrangler.jsonc`). Then either push migration changes to `main` or run the workflow manually under **Actions → db-migrate-production → Run workflow**.

**Before production migrations (checklist):** (1) **Back up** the database (snapshot, `pg_dump`, or your host’s “backup now”) so you can restore if something goes wrong. (2) **Run the same migration** on **staging** with production-like data and verify the app. (3) **Write down a rollback plan**: which migration steps are reversible, how to restore from the backup, and who can approve an emergency re-run. (4) **Store** `PRODUCTION_DATABASE_URL` only in GitHub encrypted secrets (or a password manager for operators), not in the repo. This avoids the root `dotenv` script so the shell’s `DATABASE_URL` wins over `.env` when you *do* run locally. Run against the same git revision you deploy, and plan timing so schema changes land before (or with) the app that needs them. If a hosted DB is missing `psql` access, the same URL in a trusted CI job or a one-off GitHub Action is safer than ad-hoc local shell access to production.

### Code Quality
```bash
pnpm check            # Check format and lint (read-only)
pnpm lint             # Run ESLint
pnpm format           # Format code
```

## ⚠️ Important Restrictions

**NEVER run project-wide commands:**
- ❌ `pnpm check` on entire project
- ❌ `pnpm lint` without file filter
- ❌ `pnpm format` on entire project

These cause unnecessary changes to unrelated files. Only lint/format specific files when needed.

## 🛠️ Tech Stack

- **Language**: TypeScript
- **Package Manager**: pnpm
- **Build Tool**: Turbo
- **Frontend**: Next.js, React 19, TailwindCSS
- **Backend**: tRPC, Drizzle ORM, Cloudflare Workers
- **Database**: PostgreSQL
- **Auth**: Better Auth, Google OAuth

## 🔧 Environment Setup

1. `pnpm install` - Install dependencies
2. `pnpm nizzy env` - Create `.env` from template
3. `pnpm nizzy sync` - Sync types and variables
4. `pnpm docker:db:up` - Start PostgreSQL
5. `pnpm db:push` - Create database schema
6. `pnpm dev` - Start development servers

## 📖 For More Information

- See [`../architecture/`](../architecture/) for app overview
- See [`../guides/AGENTS.md`](../guides/AGENTS.md) for AI features
- See [`../README.md`](../README.md) for complete documentation index

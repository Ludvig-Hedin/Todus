# Scripts Guide

## Active App Commands

### iOS (`apps/ios`)
```bash
bun ios                 # Open apps/ios/Todus/Todus.xcodeproj in Xcode
bun ios:simulator       # Build the native SwiftUI iOS app for Simulator
bun ios:build:preview   # Alias for the native simulator build
bun ios:build:production # Release build for a generic iOS device without signing
```

### macOS Native App (`apps/macos`)
```bash
cd apps/macos
xcodegen generate
open TodusMac.xcodeproj
```

### Web + Backend
```bash
bun dev
bun build:frontend
bun deploy:frontend
bun deploy:backend
```

## Removed From Active Use

The old `native:*` scripts were removed from root `package.json`.

Legacy app implementations are archived under `apps/archived/*` and should not be used for active development. In particular, the Expo app under `apps/archived/archived-rn` is reference-only and is not the active iOS build target.

## Development Commands

### Database
```bash
bun docker:db:up     # Start PostgreSQL
bun docker:db:down   # Stop PostgreSQL
bun db:push          # Push schema
bun db:generate      # Generate migrations
bun db:migrate       # Apply migrations (uses `.env` DATABASE_URL)
bun db:studio        # Open Drizzle Studio
```

**Production migrations (use CI by default):** The **preferred and safest** way is **GitHub Actions** → **db-migrate-production**, with the repo secret **`PRODUCTION_DATABASE_URL`** set to the same **direct PostgreSQL connection string** as the **Hyperdrive origin** (i.e. the real Postgres host—Neon, RDS, etc.—not the `hyperdrive://` handle Workers use; see `docs/development/README.md` and `HYPERDRIVE` in `apps/server/wrangler.jsonc`).

**Emergency local run only:** Pointing `DATABASE_URL` in your shell at **production** is easy to get wrong and can apply the wrong migration to the wrong cluster. If you must run `bun run --cwd apps/server db:migrate` locally, double-check the URL and env file, use a short-lived credential, and **revoke or rotate** it afterward. Prefer the workflow; reserve local runs for break-glass situations with explicit backup/rollback in place.

### Development
```bash
bun go               # Quick start
bun dev              # Start all servers
bun nizzy env        # Setup environment
bun nizzy sync       # Sync environment
```

### Quality
```bash
bun check            # Format check & lint
bun lint             # Run ESLint
bun format           # Format code
```

## Tech Stack

- **Frontend**: React Router v7, React 19, TypeScript, TailwindCSS
- **Backend**: Node.js, tRPC, Drizzle ORM
- **Database**: PostgreSQL
- **Package Manager**: bun
- **Build Tool**: Turbo

## Code Style

- 2-space indentation
- Single quotes
- 100 character line width
- Semicolons required
- TypeScript strict mode

## Important Notes

- **NEVER run project-wide `bun check/lint/format`** - only use on specific files
- Use `bun nizzy sync` after environment changes
- Run `bun db:push` after schema changes
- Run targeted checks only for files you changed before committing

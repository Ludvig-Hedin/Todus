# Scripts Guide

## Active App Commands

### iOS (`apps/ios`)
```bash
pnpm ios
pnpm ios:simulator
pnpm ios:build:preview
pnpm ios:build:production
```

### macOS Desktop Wrapper (`apps/macos`)
```bash
pnpm macos
```

### Web + Backend
```bash
pnpm dev
pnpm build:frontend
pnpm deploy:frontend
pnpm deploy:backend
```

## Removed From Active Use

The old `native:*` scripts were removed from root `package.json`.

Legacy app implementations are archived under `apps/archived/*` and should not be used for active development.

## Development Commands

### Database
```bash
pnpm docker:db:up     # Start PostgreSQL
pnpm docker:db:down   # Stop PostgreSQL
pnpm db:push          # Push schema
pnpm db:generate      # Generate migrations
pnpm db:migrate       # Apply migrations
pnpm db:studio        # Open Drizzle Studio
```

### Development
```bash
pnpm go               # Quick start
pnpm dev              # Start all servers
pnpm nizzy env        # Setup environment
pnpm nizzy sync       # Sync environment
```

### Quality
```bash
pnpm check            # Format check & lint
pnpm lint             # Run ESLint
pnpm format           # Format code
```

## Tech Stack

- **Frontend**: Next.js, React 19, TypeScript, TailwindCSS
- **Backend**: Node.js, tRPC, Drizzle ORM
- **Database**: PostgreSQL
- **Package Manager**: pnpm
- **Build Tool**: Turbo

## Code Style

- 2-space indentation
- Single quotes
- 100 character line width
- Semicolons required
- TypeScript strict mode

## Important Notes

- **NEVER run project-wide `pnpm check/lint/format`** - only use on specific files
- Use `pnpm nizzy sync` after environment changes
- Run `pnpm db:push` after schema changes
- Always run `pnpm check` before committing

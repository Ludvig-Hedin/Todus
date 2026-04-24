# Scripts Guide

## Active App Commands

### iOS (`apps/ios`)
```bash
pnpm ios                 # Open apps/ios/Todus/Todus.xcodeproj in Xcode
pnpm ios:simulator       # Build the native SwiftUI iOS app for Simulator
pnpm ios:build:preview   # Alias for the native simulator build
pnpm ios:build:production # Release build for a generic iOS device without signing
```

### macOS Native App (`apps/macos`)
```bash
cd apps/macos
xcodegen generate
open TodusMac.xcodeproj
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

Legacy app implementations are archived under `apps/archived/*` and should not be used for active development. In particular, the Expo app under `apps/archived/archived-rn` is reference-only and is not the active iOS build target.

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

- **Frontend**: React Router v7, React 19, TypeScript, TailwindCSS
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
- Run targeted checks only for files you changed before committing

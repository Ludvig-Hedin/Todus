# Agent Configuration for Todus

Todus is an open-source AI email solution built with a modern TypeScript/Next.js stack in a monorepo setup.

## Project Structure

This is a pnpm workspace monorepo with the following structure:

- `apps/mail/` - Next.js frontend email client
- `apps/server/` - Backend server
- `apps/ios/` - iOS mobile app
- `apps/macos/` - macOS desktop wrapper
- `packages/cli/` - CLI tools (`nizzy` command)
- `packages/design-tokens/` - Design system
- `packages/eslint-config/` - Shared ESLint configuration
- `packages/tsconfig/` - Shared TypeScript configuration

## Frequently Used Commands

### Development

- `pnpm go` - Quick start: starts database and dev servers
- `pnpm dev` - Start all development servers (uses Turbo)
- `pnpm docker:db:up` - Start PostgreSQL database in Docker
- `pnpm docker:db:down` - Stop and remove database container

### Build & Deploy

- `pnpm build` - Build all packages (uses Turbo)
- `pnpm build:frontend` - Build only the mail frontend
- `pnpm deploy:frontend` - Deploy frontend
- `pnpm deploy:backend` - Deploy backend

### Code Quality

- `pnpm check` - Run format check and lint
- `pnpm lint` - Run ESLint across all packages
- `pnpm format` - Format code with Prettier

### Database

- `pnpm db:push` - Push schema changes to database
- `pnpm db:generate` - Generate migration files
- `pnpm db:migrate` - Apply database migrations
- `pnpm db:studio` - Open Drizzle Studio

### Utilities

- `pnpm nizzy env` - Setup environment variables
- `pnpm nizzy sync` - Sync environment variables and types

## Tech Stack

- **Frontend**: Next.js, React 19, TypeScript, TailwindCSS, Shadcn UI
- **Backend**: Node.js, tRPC, Drizzle ORM
- **Database**: PostgreSQL
- **Authentication**: Better Auth, Google OAuth
- **Package Manager**: pnpm (v10+)
- **Build Tool**: Turbo
- **Linting**: ESLint, Oxlint, Prettier

## Development Setup

1. Install dependencies: `pnpm install`
2. Setup environment: `pnpm nizzy env`
3. Sync environment: `pnpm nizzy sync`
4. Start database: `pnpm docker:db:up`
5. Initialize database: `pnpm db:push`
6. Start development: `pnpm dev`

## Common Workflow

1. Always run `pnpm check` before committing
2. Use `pnpm nizzy sync` after environment variable changes
3. Run `pnpm db:push` after schema changes
4. Use `pnpm go` for quick development startup

## AI & Automation Features

Todus includes AI capabilities powered by:
- **AI Compose**: Write emails with AI assistance
- **Smart Labels**: Auto-categorize emails
- **Summarization**: AI-powered email summaries
- **Search**: Semantic email search
- **Chat Interface**: Natural language commands

## Important Restrictions

- **NEVER run project-wide lint/format commands** (`pnpm check`, `pnpm lint`, `pnpm format`)
- These commands format/lint the entire codebase and cause unnecessary changes
- Only use targeted linting on specific files when necessary
- Focus on specific tasks without touching unrelated files

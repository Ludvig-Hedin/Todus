# Agent Configuration for Todus

Todus is a unified productivity app built in a bun monorepo with native Apple clients, a web client, and a backend API.

## Project Structure

This is a bun workspace monorepo with the following structure:

- `apps/mail/` - React Router + Vite frontend
- `apps/server/` - Backend server
- `apps/ios/Todus/` - iOS SwiftUI app
- `apps/macos/` - macOS SwiftUI app
- `packages/cli/` - CLI tools (`nizzy` command)
- `packages/design-tokens/` - Design system
- `packages/eslint-config/` - Shared ESLint configuration
- `packages/tsconfig/` - Shared TypeScript configuration

## Frequently Used Commands

### Development

- `bun go` - Quick start: starts database and dev servers
- `bun dev` - Start all development servers (uses Turbo)
- `bun docker:db:up` - Start PostgreSQL database in Docker
- `bun docker:db:down` - Stop and remove database container

### Build & Deploy

- `bun run build` - Build all packages (uses Turbo)
- `bun build:frontend` - Build only the mail frontend
- `bun deploy:frontend` - Deploy frontend
- `bun deploy:backend` - Deploy backend

### Code Quality

- `bun check` - Run format check and lint
- `bun lint` - Run ESLint across all packages
- `bun format` - Format code with Prettier

### Database

- `bun db:push` - Push schema changes to database
- `bun db:generate` - Generate migration files
- `bun db:migrate` - Apply database migrations
- `bun db:studio` - Open Drizzle Studio

### Utilities

- `bun nizzy env` - Setup environment variables
- `bun nizzy sync` - Sync environment variables and types

## Tech Stack

- **Frontend**: Next.js, React 19, TypeScript, TailwindCSS, Shadcn UI
- **Backend**: Node.js, tRPC, Drizzle ORM
- **Database**: PostgreSQL
- **Authentication**: Better Auth, Google OAuth
- **Package Manager**: Bun 1.3.10
- **Build Tool**: Turbo
- **Linting**: ESLint, Oxlint, Prettier

## Development Setup

1. Install dependencies: `bun install`
2. Setup environment: `bun nizzy env`
3. Sync environment: `bun nizzy sync`
4. Start database: `bun docker:db:up`
5. Initialize database: `bun db:push`
6. Start development: `bun dev`

## Common Workflow

1. Run targeted checks only for files you changed before committing
2. Use `bun nizzy sync` after environment variable changes
3. Run `bun db:push` after schema changes
4. Use `bun go` for quick development startup

## AI & Automation Features

Todus includes AI capabilities powered by:
- **AI Compose**: Write emails with AI assistance
- **Smart Labels**: Auto-categorize emails
- **Summarization**: AI-powered email summaries
- **Search**: Semantic email search
- **Chat Interface**: Natural language commands

## Important Restrictions

- **NEVER run project-wide lint/format commands** (`bun check`, `bun lint`, `bun format`)
- These commands format/lint the entire codebase and cause unnecessary changes
- Only use targeted linting on specific files when necessary
- Focus on specific tasks without touching unrelated files

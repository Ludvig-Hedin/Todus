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

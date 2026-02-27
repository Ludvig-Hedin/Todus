# Comprehensive Terminal Commands Guide

This guide provides a consolidated list of common terminal commands used in this project for setup, development, testing, deployment, and maintenance.

## Table of Contents

- [Project Setup & Installation](#project-setup--installation)
- [Development Server](#development-server)
- [Linting and Formatting](#linting-and-formatting)
- [Testing](#testing)
- [Database Management (Supabase & Drizzle)](#database-management-supabase--drizzle)
- [Building for Production](#building-for-production)
- [Deployment](#deployment)
- [Git Workflow and Versioning](#git-workflow-and-versioning)
- [Local Backups](#local-backups)
- [MCP Server Management (If Applicable)](#mcp-server-management-if-applicable)

Claude Commands:
claude --dangerously-skip-permissions

---

Codex Commands:
codex -a never

---

## Clean cache and resinstall things

# 1. Kill any process using port 5555

# 2. Remove npm/yarn/pnpm lockfiles

# 3. Remove node_modules

# 4. Remove Next.js cache

# 5. Reinstall dependencies

# 6. Start dev server

# 7. Check for any lingering processes

# 8. Check for any lingering files

# 1. Kill any process

lsof -ti:3000 | xargs kill -9 2>/dev/null
pkill -f "next dev" 2>/dev/null

# Clean cache and reinstall dependencies

## Web APP

rm .next
rm -rf .next
rm node_modules
rm -rf node_modules
rm package-lock.json
npm cache clean --force
npm install
PORT=3100 npm run dev

## Mobile

rm -rf .expo node_modules/.cache
rm -rf node_modules
rm package-lock.json
npm cache clean --force
npm install

npx expo start --clear -c
npx expo start --clear -c --tunnel
--dev-client

npx expo prebuild --clean
npx expo run:ios
npx expo run:ios --device

npm -C web run dev

---

# Codex

Available slash commands

Slash command Description
/auto-context Turn Auto Context on or off to include recent files and IDE context automatically.
/cloud Switch to cloud mode to run the task remotely (requires cloud access).
/cloud-environment Choose the cloud environment to use (available only in cloud mode).
/feedback Open the feedback dialog to submit feedback and optionally include logs.
/local Switch to local mode to run the task in your workspace.
/review Start code review mode to review uncommitted changes or compare against a base branch.
/status Show the thread ID, context usage, and rate limits.

Command Purpose When to use it
/approvals Set what Codex can do without asking first. Relax or tighten approval requirements mid-session, such as switching between Auto and Read Only.
/diff Show the Git diff, including files Git isn’t tracking yet. Review Codex’s edits before you commit or run tests.
/review Ask Codex to review your working tree. Run after Codex completes work or when you want a second set of eyes on local changes.
/undo  Revert Codex’s most recent turn.

Global Flags:
Key Type / Values Details
--add-dir path Grant additional directories write access alongside the main workspace. Repeat for multiple paths.
--ask-for-approval, -a untrusted | on-failure | on-request | never Control when Codex pauses for human approval before running a command.
--cd, -C path Set the working directory for the agent before it starts processing your request.
--config, -c key=value Override configuration values. Values parse as JSON if possible; otherwise the literal string is used.
--dangerously-bypass-approvals-and-sandbox, --yolo boolean Run every command without approvals or sandboxing. Only use inside an externally hardened environment.
--disable feature Force-disable a feature flag (translates to `-c features.<name>=false`). Repeatable.
--enable feature Force-enable a feature flag (translates to `-c features.<name>=true`). Repeatable.
--full-auto boolean Shortcut for low-friction local work: sets `--ask-for-approval on-request` and `--sandbox workspace-write`.
--image, -i path[,path...] Attach one or more image files to the initial prompt. Separate multiple paths with commas or repeat the flag.
--model, -m string Override the model set in configuration (for example `gpt-5-codex`).
--search boolean Enable web search. When true, the agent can call the `web_search` tool without asking every time.

--

Create ~/.codex/prompts/prompt-name.md with reusable guidance:

---

description: lorem ipsum dolor sit amet
argument-hint: [FILES=<paths>] [PR_TITLE="<title>"]
---

Prompt goes here:Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.

---

Invoke and manage custom commands

In Codex (CLI or IDE extension), type / to open the slash command menu.

Enter prompts: or the prompt name, for example /prompts:draftpr.

Supply required arguments:

/prompts:draftpr FILES="src/pages/index.astro src/lib/api.ts" PR_TITLE="Add hero animation"

Press Enter to send the expanded instructions (skip either argument when you don’t need it).

## Development Server

### Run the Next.js Development Server

```bash
npm run dev
```

This will typically start the server on `http://localhost:3000`.

---

## Linting and Formatting

### Run ESLint

```bash
npm run lint
```

### Run Biome Formatter/Linter

```bash
npm run format
# or to check formatting
npm run format:check
# or to lint with Biome
npm run lint:biome
```

---

## Testing

### Run Unit and Integration Tests (Vitest)

```bash
npm test
# or with watch mode
npm run test:watch
```

### Run End-to-End Tests (Playwright)

```bash
# First, ensure browsers are installed for Playwright
npm run playwright install

# Run E2E tests
npm run test:e2e
```

---

## Database Management (Supabase & Drizzle)

### 1. Drizzle Migrations

**Generate a new migration after schema changes:**

```bash
npm run db:generate
```

Review the generated SQL migration file in `src/lib/db/migrations/` before applying.

**Apply pending migrations to your local Supabase database:**

```bash
npm run db:push
```

Alternatively, to apply migrations to a remote or specific Supabase instance, ensure your `DATABASE_URL` in `.env.local` points to the correct database.

**Apply migrations (alternative, if `db:push` is not suitable for your workflow):

```bash
npm run db:migrate
```

### 2. Drizzle Studio (Local Database Browser)

```bash
npm run db:studio
```

### 3. Supabase CLI (If managing Supabase project locally or for advanced operations)

**Ensure you have the Supabase CLI installed and are logged in.**

```bash
# Login to Supabase (one-time setup)
supabase login

# Link your local project to your Supabase project (run in project root)
# supabase link --project-ref YOUR_PROJECT_ID
# (Follow instructions, get project ID from your Supabase dashboard URL)

# Start local Supabase services (Docker required)
supabase start
```

This will output local Supabase URLs and keys, which you might need to put in your `.env.local` for local development against a local Supabase instance.

**Stop local Supabase services:**

```bash
supabase stop
```

**Access local Supabase Studio:**
After `supabase start`, the CLI usually provides a URL for Studio (e.g., `http://localhost:54323`).

**Pull remote database changes (e.g., schema changes made via Supabase Dashboard):**

```bash
# supabase db pull
```

### 4. Seeding the Database

If you have seed scripts defined in `package.json` or `scripts/`:

```bash
# Example command, adjust if your script is named differently
npm run db:seed
```

---

## Building for Production

### Create a Production-Ready Build

```bash
npm run build
```

This will create an optimized build in the `.next` directory.

---

## Deployment

This project is typically deployed to Vercel.

### Deploy to Vercel (using Vercel CLI)

Ensure you have the Vercel CLI installed and are logged in.

```bash
# Install Vercel CLI globally (if not already installed)
# npm install -g vercel

# Login to Vercel (one-time setup)
# vercel login

# Link project to Vercel (run in project root, first time setup)
# vercel link

# Deploy to a preview environment
vercel deploy

# Deploy to production
vercel deploy --prod
```

Alternatively, Vercel deployments are often handled automatically via Git integration upon pushes to specific branches (e.g., `main` or `develop`).

---

## Git Workflow and Versioning

(Content from previous `TERMINAL_COMMANDS.md` - translated and adapted)

### 1. Connect to Your GitHub Repository

If you haven't already initialized Git:

```bash
git init
git remote add origin https://github.com/Ludvig-Hedin/AA-MCP-MVP.git
```

If you already have a `.git` folder and want to set/change the remote URL:

```bash
git remote set-url origin https://github.com/Ludvig-Hedin/AA-MCP-MVP.git
```

### 2. Create a New Branch

```bash
git checkout -b <branch-name>
```

Example:

```bash
git checkout -b feature/new-chat-interface
```

### 3. Recommended Branch Structure (Gitflow Inspired)

- **`main`**: Always stable, production-ready code. Represents released versions.
- **`develop`**: Primary development branch. Contains the latest delivered development changes for the next release. When stable, it's merged into `main` and tagged.
- **`feature/<descriptive-name>`**: For new features or significant changes. Branched from `develop` and merged back into `develop`.
  (e.g., `feature/user-preferences-api`)
- **`fix/<descriptive-name>`** or **`bugfix/<descriptive-name>`**: For bug fixes. Branched from `develop` (or `main` for hotfixes) and merged back.
  (e.g., `fix/login-redirect-loop`)
- **`release/vX.Y.Z`**: For preparing a new production release. Branched from `develop`. Allows for final testing, bug fixes, and documentation updates before merging to `main` and `develop`.
- **`hotfix/vX.Y.Z`**: For critical fixes to a production release. Branched from `main` (from the corresponding tag) and merged back into `main` and `develop`.

Example of starting a feature:

```bash
git checkout develop
git pull origin develop
git checkout -b feature/awesome-new-feature
```

### 4. Push a Branch to GitHub

```bash
git push -u origin <branch-name>
```

Example:

```bash
git push -u origin feature/awesome-new-feature
```

### 5. Keeping Your Workspace Clean and Up-to-Date

**Fetch latest changes from remote:**

```bash
git fetch origin
```

**Update your local `develop` branch:**

```bash
git checkout develop
git pull origin develop
```

**Rebase your feature branch on the latest `develop` (preferred over merging `develop` into feature branch to keep history linear):**

```bash
git checkout feature/awesome-new-feature
git rebase develop
# Resolve any conflicts, then:
git push --force-with-lease origin feature/awesome-new-feature
```

**Merging a feature branch (usually done via Pull Request on GitHub):**
Once a feature is complete and reviewed, it's merged into `develop` via a Pull Request.

### 6. Tagging Releases (Semantic Versioning vX.Y.Z)

When `develop` is merged into `main` for a release, create an annotated tag:

```bash
git checkout main
git pull origin main # Ensure main is up-to-date
git tag -a v1.0.0 -m "Release version 1.0.0: Initial launch with core features"
git push origin v1.0.0
```

### Tips for Version Names/Tags (Examples)

- **Stable versions:** `v1.0.0`, `v1.0.1`, `v1.1.0`
- **Pre-releases (if needed):** `v1.0.0-alpha.1`, `v1.0.0-beta.2`

(Original Swedish content on branch naming conventions like `day/yyyy-mm-dd` or `legacy-v1` can be adapted if still relevant, but the Gitflow model above is more standard.)

---

## Local Backups

Refer to `docs/LOCAL_BACKUP_GUIDE.md` for detailed strategies. Common commands might include:

### Creating a ZIP Archive of the Project (excluding `node_modules`, `.git`, etc.)

```bash
# Example command (syntax might vary by OS or installed tools)
# On macOS/Linux:
zip -r project_backup_$(date +%Y-%m-%d).zip . -x "node_modules/*" -x ".git/*" -x ".next/*" -x "*.log"
```

### Creating a Local Bare Git Clone (for Git history backup)

```bash
# Navigate to the directory where you want to store backups
cd /path/to/your/backups
git clone --bare /path/to/your/AA-MCP-MVP project_backup.git
```

To update this bare clone later:

```bash
cd /path/to/your/backups/project_backup.git
git fetch origin --prune
```

---

## MCP Server Management (If Applicable)

If you are running any MCP servers locally (e.g., the `custom-mcp-server` provided in the project or others):

### Example: Running the `custom-mcp-server`

(Assuming it has a `start` script in its `package.json`)

```bash
cd custom-mcp-server
npm install # If first time or dependencies changed
npm start   # Or whatever the start command is
```

Consult the specific README or documentation for each local MCP server you intend to run.

---

*This guide should be updated as project dependencies, tools, or workflows change.*

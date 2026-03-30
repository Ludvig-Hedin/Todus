# Todus Project Context

## Project Overview

**Todus** is an open-source, AI-driven email solution designed for self-hosting while also integrating with external services like Gmail. The project emphasizes data privacy, self-hosting freedom, a unified inbox, and high customizability.

### Architecture
Todus is structured as a **pnpm + Turborepo monorepo** containing multiple applications and shared packages:
- **Apps (`apps/`)**:
  - `mail`: The main web frontend built with **Next.js, React 19, TypeScript, TailwindCSS, and Shadcn UI**.
  - `ios`: The iOS mobile app built with **React Native and Expo**.
  - `macos`: The desktop application.
  - `server`: The backend service built with **Node.js, Drizzle ORM, and PostgreSQL**.
- **Packages (`packages/`)**:
  - Contains shared libraries such as `api-client`, `design-tokens`, `ui-native`, `swift-auth`, `testing`, and `shared`.

### Core Technologies
- **Frontend:** Next.js, React, React Native, Expo, TailwindCSS, Shadcn UI
- **Backend:** Node.js, Better Auth (Auth), Drizzle ORM (Database ORM)
- **Database:** PostgreSQL (Run locally via Docker)
- **Tooling:** pnpm workspaces, Turborepo, TypeScript, Prettier, ESLint/oxlint

---

## Building and Running

### Prerequisites
- Node.js (v18+)
- pnpm (v10+)
- Docker (v20+)

### Setup Instructions
1. Install dependencies:
   ```bash
   pnpm install
   ```
2. Setup Environment Variables:
   ```bash
   pnpm nizzy env
   pnpm nizzy sync
   ```
3. Start the local Database:
   ```bash
   pnpm docker:db:up
   ```
4. Initialize the database schema:
   ```bash
   pnpm db:push
   ```

### Common Commands
- **Start Web Development Server:** `pnpm dev`
- **Start iOS Simulator:** `pnpm ios:simulator`
- **Start macOS App Dev:** `pnpm macos`
- **Database Studio:** `pnpm db:studio` (Runs automatically with `pnpm dev`)
- **Lint Codebase:** `pnpm lint`
- **Format Code:** `pnpm run format`
- **Run Tests:** `pnpm test` (Uses `@zero/testing` package)

---

## Development Conventions

- **Monorepo Workflow:** Always use `pnpm` and respect the workspace structure (`pnpm-workspace.yaml`). Add dependencies to specific workspaces using the `--filter` flag when applicable.
- **Typing:** The project relies heavily on strict TypeScript. Type definitions and TS configs are shared from `packages/tsconfig`.
- **Styling:** TailwindCSS is the standard for styling web components, and shared tokens (`packages/design-tokens`) should be utilized for cross-platform consistency.
- **Formatting:** Code formatting is enforced via Prettier (`prettier --write`). Linting combines Turbo cache with `oxlint` and standard ESLint.
- **Database Migrations:** Modifying the Drizzle schema requires running `pnpm db:generate` followed by `pnpm db:migrate` or `pnpm db:push`.
- **API integrations:** The backend interfaces with external systems like Gmail API, Twilio, and Autumn. Ensure to strictly follow authentication setup when testing features requiring these services.

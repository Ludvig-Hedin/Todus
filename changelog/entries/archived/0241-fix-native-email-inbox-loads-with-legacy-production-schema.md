---
id: 0241
title: "Fix — Native email inbox loads with legacy production schema"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

## [2026-04-25] Fix — Native email inbox loads with legacy production schema

- [Fix] **Backend:** Native iOS/macOS mail endpoints now tolerate production databases that have not yet applied the connection color / assistant second-brain migrations. `mail.listThreads` can resolve the active connection without selecting `mail0_connection.color`, multi-connection reads use the same fallback, and `assistant.listOpenLoops` returns an empty nudges list instead of failing when assistant tables are missing.
- [Fix] **Backend:** Bearer-token requests no longer have their real connection error masked by a failed Better Auth sign-out/get-session path.
- [User-facing] Restores native Email Inbox loading instead of showing "Couldn't load Inbox / Failed to load emails."
- **Files:** `apps/server/src/lib/server-utils.ts`, `apps/server/src/trpc/trpc.ts`, `apps/server/src/trpc/routes/connections.ts`, `apps/server/src/trpc/routes/assistant.ts`, `apps/server/src/main.ts`

---
id: 0084
title: "Feature — web: iOS/macOS feature parity (Folders, AI Chat, Global Search)"
status: archived
category: Added
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Feature — web: iOS/macOS feature parity (Folders, AI Chat, Global Search)

- **Task Folders**: Tasks page now has a folder sidebar (create/rename/delete folders, filter tasks by folder, move tasks to folders via dropdown). Backend `folders.list/create/update/delete` tRPC routes fully wired.
- **AI Chat page** (`/mail/chat`): Standalone full-page chat using `useAgent` + `useAgentChat` from Cloudflare `agents` SDK. Connects to `ZeroAgent` Durable Object via WebSocket. Example queries, streaming indicator, stop button.
- **Global Search page** (`/mail/search`): Searches both emails (via `mail.listThreads` with `q` param) and tasks (via `tasks.list` with `search` param) simultaneously. Tabbed result view (All / Emails / Tasks), debounced input, empty/loading states.
- **Navigation**: Added AI Chat and Search items to sidebar "Organize" section with keyboard shortcuts. Added `navigation.sidebar.chat` and `navigation.sidebar.search` i18n keys.
- **Routes**: Registered `/mail/chat` and `/mail/search` in `routes.ts`.

**Files:** `apps/web/app/(routes)/mail/tasks/page.tsx`, `apps/web/app/(routes)/mail/chat/page.tsx` (new), `apps/web/app/(routes)/mail/search/page.tsx` (new), `apps/web/app/routes.ts`, `apps/web/config/navigation.ts`, `apps/web/messages/en.json`

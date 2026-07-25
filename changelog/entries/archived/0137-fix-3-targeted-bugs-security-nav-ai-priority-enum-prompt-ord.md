---
id: 0137
title: "Fix — 3 targeted bugs: security nav, AI priority enum, prompt ordering"
status: archived
category: Security
release_date: 2026-03-31
source: CHANGELOG.md
---

## [2026-03-31] Fix — 3 targeted bugs: security nav, AI priority enum, prompt ordering

- **Security nav missing**: Added `navigation.settings.security` entry to `apps/web/config/navigation.ts` so the Active Sessions page (`/settings/security`) is reachable from the settings sidebar. Route and i18n key already existed; the nav link was the only missing piece.
- **Stale 'urgent' priority in AI tool definitions**: Removed `'urgent'` from the priority enum in both `create_task` and `update_task` tool definitions in `apps/server/src/routes/ai.ts`. The server tRPC schema (`tasks.ts`) only accepts `['none','low','medium','high']`; any AI-generated `priority: 'urgent'` would fail validation.
- **AI profile prepended before system prompt**: Flipped ordering in `apps/server/src/routes/agent/index.ts` (ZeroAgent) and `apps/server/src/routes/ai.ts` (`/ai/chat` and `/ai/call`) so the base system instructions appear first and user profile context is appended after, ensuring core rules are not shadowed by user content.

**User-facing:** Security page now appears in settings sidebar. AI task creation with priority no longer silently fails. AI assistant behavior is more stable when users set custom profiles.

**Files:** `apps/web/config/navigation.ts`, `apps/server/src/routes/ai.ts`, `apps/server/src/routes/agent/index.ts`

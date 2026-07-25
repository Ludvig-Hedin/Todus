---
id: 0112
title: "Fix — `@zero/web` index route & routing parity with `apps/mail`"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — `@zero/web` index route & routing parity with `apps/mail`

**Symptom:** Visiting `http://localhost:3000/` showed a non-interactive calendar stub with no sidebar or mail chrome.

**Root cause:** `react-router.config.ts` uses `appDirectory: 'app'`, so `index('page.tsx')` resolves to **`app/page.tsx`**, which had been a placeholder calendar — not the marketing `HomeContent` shell from `apps/mail`. The experimental `app-layout.tsx` wrapper also did not apply to `/`, so the index never matched the unified shell.

**Fix:** Replaced `app/page.tsx` with the same pattern as `apps/mail` (`HomeContent` + `clientLoader` redirect to `/mail/inbox` when authenticated). Replaced **`app/routes.ts`** with the same tree as **`apps/mail/app/routes.ts`** (removed outer `app-layout` and `/home`/`/tasks`/`/calendar` routes under that layout). Removed duplicate/orphan files: root `apps/web/page.tsx`, `app/app-layout.tsx`, `(routes)/home|tasks|calendar/page.tsx`.

**User-facing:** Logged-in users land in the real mail app (`AppSidebar`, folders, working mail UI). Guests still get the marketing home.

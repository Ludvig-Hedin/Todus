---
id: 0194
title: "Web App Catch-Up Sync — Mirror `apps/mail` into `apps/web`"
status: archived
category: Changed
release_date: 2026-04-04
source: CHANGELOG.md
---

## [2026-04-04] Web App Catch-Up Sync — Mirror `apps/mail` into `apps/web`

### Web (`apps/web`)

- **Canonical source restored:** Synced the newer web-facing changes that had been applied in `apps/mail` over to `apps/web`, while intentionally leaving `apps/mail` unchanged.
- **Route parity:** Brought `apps/web` up to date with the newer route/layout surface from `apps/mail`, including docs, meetings, sharing, and group-join/chat related pages.
- **UI parity:** Mirrored the latest mail/home/tasks/search/settings/navigation/sidebar/thread-view updates so `apps/web` matches the newer app behavior and information architecture already present in `apps/mail`.
- **Multi-account and refresh UX parity:** Carried over the connection filter provider, background refresh indicator, optimistic cache/task updates, and related mailbox/thread rendering changes that had diverged.
- **Translations:** Synced the localized message catalogs that the newer web surfaces depend on.

### Verification

- `pnpm --filter @zero/web build` [Passed]

---
id: 0195
title: "Multi-Account Support — Backend, Web, iOS, macOS"
status: archived
category: Changed
release_date: 2026-04-04
source: CHANGELOG.md
---

## [2026-04-04] Multi-Account Support — Backend, Web, iOS, macOS

### Backend (`apps/server`)

- **Schema:** Added `color` column to `connection` table (migration `0047_connection_color.sql`) for per-account visual differentiation.
- **Middleware:** New `multiConnectionProcedure` in `trpc.ts` that resolves ALL user connections (not just default) for multi-account endpoints.
- **`mail.listThreadsMulti`:** New endpoint that fetches threads from multiple connections in parallel, merges and sorts by date, returns threads tagged with `connectionId/connectionEmail/connectionColor`, handles partial failures gracefully.
- **`calendar.eventsMulti`:** New endpoint that fetches calendar events from all Google connections in parallel, merges and sorts by start time.
- **`connections.updateColor`:** New mutation to update a connection's display color.
- **`connections.list/getDefault`:** Now includes `color` field in response (auto-assigned from palette if not set).

### Web (`apps/mail`)

- **ConnectionFilterProvider:** New React context (`providers/connection-filter-provider.tsx`) managing which connections are visible, persisted to localStorage. Default: all enabled.
- **nav-user.tsx:** Evolved account avatars from click-to-switch to click-to-toggle-visibility. Each account shows a colored ring (connection color) when enabled, reduced opacity when hidden. Right-click context menu for "Set as default". Star icon on default account.
- **use-threads.ts:** Updated to call `listThreadsMulti` when multiple connections are enabled (unified view), falls back to original `listThreads` for single-connection efficiency.
- **mail-list.tsx:** Added colored dot indicator on thread rows when in unified multi-account view, with tooltip showing account email.
- **email-composer.tsx:** Enhanced "From:" picker to show all connected accounts with colored dots alongside aliases.

### Shared Auth (`packages/swift-auth`)

- **AuthService:** Added `linkSocialAccount(provider:)` method for linking additional OAuth accounts to an existing authenticated user via ASWebAuthenticationSession.
- **AuthError:** Added `notAuthenticated` and `networkError` cases.

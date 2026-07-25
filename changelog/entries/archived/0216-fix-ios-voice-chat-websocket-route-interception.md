---
id: 0216
title: "Fix — iOS voice chat WebSocket route interception"
status: archived
category: Fixed
release_date: 2026-04-24
source: CHANGELOG.md
---

## [2026-04-24] Fix — iOS voice chat WebSocket route interception

- [Fix] Scoped the server tRPC middleware to `/trpc/*` inside the `/api` sub-app and corrected its endpoint to `/trpc`, so `/api/ai/voice-ping` and `/api/ai/voice-ws` now reach the AI router instead of being misparsed as tRPC procedure paths.
- [Fix] This restores the iOS voice-chat WebSocket upgrade path that was surfacing as `NSURLErrorDomain Code=-1011` / “There was a bad response from the server.”
- [Architectural] The regression was in backend route registration, not the iOS audio stack: the broad tRPC middleware was shadowing sibling `/api/ai/*` routes after the `/api` mount.
- [Fix] iOS voice chat now refreshes an expiring native bearer token before starting the WebSocket handshake, so the voice session no longer fails with a `401` upgrade when the app is otherwise still signed in.
- **Files:** `apps/server/src/main.ts`

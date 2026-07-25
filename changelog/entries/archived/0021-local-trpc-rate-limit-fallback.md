---
id: 0021
title: "Local tRPC Rate Limit Fallback"
status: archived
category: Changed
release_date: 2026-03-08
source: CHANGELOG.md
---

## [2026-03-08] Local tRPC Rate Limit Fallback

### Fixed

- **Local Settings/Labels 500s**: Resolved `settings.get` and `labels.list` failing with `Invalid token` when the local Redis/Upstash token is expired or mismatched.
- **tRPC Redis Resilience**: Updated `apps/server/src/trpc/trpc.ts` so rate-limited procedures keep working in `local` and `development` when Redis is unavailable, while still enforcing rate limits normally when Redis is healthy.

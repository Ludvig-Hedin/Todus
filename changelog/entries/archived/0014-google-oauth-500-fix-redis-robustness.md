---
id: 0014
title: "Google OAuth 500 Fix & Redis Robustness"
status: archived
category: Fixed
release_date: 2026-03-01
source: CHANGELOG.md
---

## [2026-03-01] Google OAuth 500 Fix & Redis Robustness

### Fixed

- **OAuth Callback**: Resolved a 500 Internal Server Error during Google OAuth login caused by an invalid `REDIS_TOKEN`.
- **Redis Resilience**: Implemented a `try/catch` fallback mechanism in `apps/server/src/lib/auth.ts` to gracefully switch to PostgreSQL session storage if Redis connection fails (e.g., due to expired/invalid tokens).
- **Cleanup**: Removed temporary debug instrumentation from `main.ts`.
- **Onboarding Assets**: Fixed broken image/animation links in the onboarding modal by switching from non-resolving `assets.todus.app` to local `/public/onboarding` assets.

---
id: 0086
title: "Fix — archived RN parity and safety cleanup"
status: archived
category: Fixed
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Fix — archived RN parity and safety cleanup

- Hardened the archived RN auth, settings, and mail flows against stale optimistic state, unhandled URL opening errors, and unsafe persistence failures.
- Removed raw email from native PostHog identification, added safer Postgres healthcheck behavior in production compose, and closed Hyperdrive connections in the server auth token path.
- Updated shared compose/mail helpers and several settings screens to handle loading, error, and accessibility cases more defensively.

**Files:** `apps/server/src/main.ts`, `docker-compose.prod.yaml`, `apps/archived/archived-rn/...`

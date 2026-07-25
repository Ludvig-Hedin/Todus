---
id: 0020
title: "Local Mail Auto-Sync Fallback"
status: archived
category: Changed
release_date: 2026-03-08
source: CHANGELOG.md
---

## [2026-03-08] Local Mail Auto-Sync Fallback

### Fixed

- **Local Inbox Freshness**: Added a local-only auto-sync fallback that periodically triggers the existing `mail.forceSync` path and refreshes the inbox data, so new emails appear during local development without relying on Gmail push webhooks.
- **Production Safety**: Kept this behavior gated to Vite dev sessions pointed at a localhost backend, leaving staging and production mail sync behavior unchanged.

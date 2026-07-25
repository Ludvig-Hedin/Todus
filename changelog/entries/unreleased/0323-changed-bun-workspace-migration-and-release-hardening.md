---
id: 0323
title: "Changed — Bun workspace migration and release hardening"
status: unreleased
category: Fixed
release_date: 2026-07-24
source: CHANGELOG.md
---

### Changed — Bun workspace migration and release hardening, 2026-07-24

- Migrated the monorepo from pnpm to Bun 1.3.10 across workspace metadata, the lockfile, CI, Docker, scripts, and current operational docs. The Bun lockfile was generated from the prior pnpm lock so the migration preserves resolved dependency versions.
- Fixed Bun workspace filters, pinned Bun in container images, and corrected the Nizzy postinstall to recognize the Todus root and generate types for the active `apps/web` frontend.
- Removed the stale tracked `.claude/worktrees` gitlink from the parent repository while preserving the registered local worktree and its dirty state.

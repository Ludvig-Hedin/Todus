---
id: 0047
title: "Open source — secret hygiene & CI"
status: archived
category: Changed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] Open source — secret hygiene & CI

### Security (contributor-facing)

- **Audited repo**: No real API keys or OAuth secrets found in tracked source; secrets belong in `.env` / `.dev.vars` / `wrangler secret` (all gitignored or dashboard-only).
- **`apps/server/wrangler.jsonc` (local)**: Removed numeric placeholders for `ELEVENLABS_API_KEY` and `VOICE_SECRET` (empty in `vars`); clarified dev JWT placeholder string. Added comment that real secrets must not live in committed `vars`.
- **`apps/server/src/env.ts`**: `JWT_SECRET` / `ELEVENLABS_API_KEY` typings widened to `string` (no fake literals).
- **`.gitignore`**: Ignore common credential filename patterns (`*credentials*.json`, Google service account blobs, etc.).
- **`SECURITY.md`**: Guidelines for reporting issues, forks, and never committing secrets.
- **`.github/workflows/gitleaks.yml`**: Gitleaks on pull requests.

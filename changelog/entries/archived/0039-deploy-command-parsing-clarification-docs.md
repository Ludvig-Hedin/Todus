---
id: 0039
title: "Deploy Command Parsing Clarification (Docs)"
status: archived
category: Docs
release_date: 2026-03-26
source: CHANGELOG.md
---

## [2026-03-26] Deploy Command Parsing Clarification (Docs)

### Fixed

- **Deploy Usage**: Clarified that inline `# ...` text after `pnpm run` commands may be forwarded as real CLI args to Wrangler (triggering `Unknown arguments`), and showed the correct deploy commands (`pnpm run deploy:backend` / `pnpm run deploy:frontend`). (docs/terminal-commands.md)
- **Env Selection**: Updated deployment docs to run Wrangler via `pnpm --filter=... exec wrangler` and explicitly pass `-e staging` / `-e production` (avoids relying on pnpm script argument passthrough and fixes “wrangler: command not found”). (docs/terminal-commands.md)

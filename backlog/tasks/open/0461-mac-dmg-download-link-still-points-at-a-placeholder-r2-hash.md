---
id: 0461
title: "Mac DMG download link still points at a placeholder R2 hash"
status: open
priority: P1
tags: [web, todo-sweep, downloads]
files: [apps/web/app/(full-width)/downloads.tsx]
created: 2026-07-25
source: code TODO/FIXME sweep
---

`MAC_DMG_URL` is `https://pub-REPLACE_WITH_HASH.r2.dev/mac/Todus-1.0.dmg` — the placeholder was never replaced, so the Mac download button on `/downloads` resolves to a dead host.

```
apps/web/app/(full-width)/downloads.tsx:12
// TODO: Replace REPLACE_WITH_HASH with the actual hash from:
// `cd apps/server && npx wrangler r2 bucket dev-url get todus-releases`
```

## Fix shape

Read the real public bucket URL (`npx wrangler r2 bucket dev-url get todus-releases`) and either inline it or move it to a build-time env var so a bucket rotation does not need a code change. Needs Cloudflare access — see `user-tasks/` if the value has to come from the account owner.

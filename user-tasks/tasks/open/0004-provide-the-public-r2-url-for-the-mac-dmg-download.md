---
id: 0004
title: "Provide the public R2 URL for the Mac DMG download"
status: open
priority: P1
area: infra
source: "code TODO sweep — apps/web/app/(full-width)/downloads.tsx (backlog 0461)"
created: 2026-07-25
---

`/downloads` links to `https://pub-REPLACE_WITH_HASH.r2.dev/mac/Todus-1.0.dmg`. The placeholder host does not resolve, so the Mac download button is broken in production.

- [ ] Run `cd apps/server && npx wrangler r2 bucket dev-url get todus-releases` (needs Cloudflare auth for the account that owns the bucket)
- [ ] Paste the returned public URL into this task
- [ ] Decide whether it lives inline or as a build-time env var for `@zero/web`

Once the value is here, backlog item `0461` can land the code change.

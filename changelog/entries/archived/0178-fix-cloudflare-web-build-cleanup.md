---
id: 0178
title: "Fix — Cloudflare web build cleanup"
status: archived
category: Fixed
release_date: 2026-04-03
source: CHANGELOG.md
---

## [2026-04-03] Fix — Cloudflare web build cleanup

### Web (`apps/mail`)

- **apps/mail/app/(routes)/mail/docs/[docId]/page.tsx**: Fixed the doc editor import to use the default `Editor` export from `@/components/create/editor`, resolving the Rollup/Vite missing export build error.
- **apps/mail/components/mail/note-panel.tsx**: Replaced `window.confirm` with the existing shadcn dialog pattern for note deletion so the code passes the `no-alert` lint rule without suppressions.
- **apps/mail/app/(auth)/todus/login/page.tsx** and **apps/mail/app/(auth)/todus/signup/page.tsx**: Removed dead `false && (...)` JSX branches and the now-unused auth form code so Oxlint no longer flags constant boolean conditions.

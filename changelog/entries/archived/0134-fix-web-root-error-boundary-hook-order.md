---
id: 0134
title: "Fix — web root error boundary hook order"
status: archived
category: Fixed
release_date: 2026-03-31
source: CHANGELOG.md
---

## [2026-03-31] Fix — web root error boundary hook order

- Split the root error boundary in `apps/mail/app/root.tsx` so the 404 branch returns before any hooks and the Sentry/reporting side effects live in a dedicated child component. This removes the conditional hook call that violated `react-hooks/rules-of-hooks`.

**Files:** `apps/mail/app/root.tsx`, `TASK.md`

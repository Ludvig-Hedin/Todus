---
id: 0133
title: "Fix — categories settings state sync"
status: archived
category: Fixed
release_date: 2026-03-31
source: CHANGELOG.md
---

## [2026-03-31] Fix — categories settings state sync

- Updated `apps/mail/app/(routes)/settings/categories/page.tsx` so the local categories state rehydrates from `initialCategories` when fresh server data arrives, instead of relying on a stale effect dependency. Also removed the loose `any` type from the field-change prop.

**Files:** `apps/mail/app/(routes)/settings/categories/page.tsx`, `TASK.md`

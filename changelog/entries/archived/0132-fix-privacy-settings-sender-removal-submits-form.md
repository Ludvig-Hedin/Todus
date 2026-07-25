---
id: 0132
title: "Fix — privacy settings sender removal submits form"
status: archived
category: Removed
release_date: 2026-03-31
source: CHANGELOG.md
---

## [2026-03-31] Fix — privacy settings sender removal submits form

- Added `type="button"` to the trusted-sender removal control in `apps/mail/app/(routes)/settings/privacy/page.tsx` so clicking the remove icon no longer triggers the surrounding form submit.

**Files:** `apps/mail/app/(routes)/settings/privacy/page.tsx`, `TASK.md`

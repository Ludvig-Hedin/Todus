---
id: 0129
title: "Auto-fixed (1)"
status: done
tags: [web, bug-hunt, code-review-backlog]
files: []
created: 2026-05-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-20 — Bug Hunt: apps/web main user flows

## Auto-fixed (1)

| File:line | Severity | What changed |
|-----------|----------|--------------|
| `apps/web/app/(routes)/mail/calendar/page.tsx:174-181` | error | useEffect deps included `displayMonth`, so any user-initiated month-pagination via Calendar's `onMonthChange` re-fired the effect and snapped `displayMonth` back to `selectedDate`'s month. Users could not paginate the picker without also clicking a date. Removed `displayMonth` from deps (eslint-disable for exhaustive-deps); effect now runs only on `selectedDate` change. |

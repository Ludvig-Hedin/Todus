---
id: 0121
title: "Resolved in 2026-03-31 Review Session"
status: done
tags: [code-review, code-review-backlog]
files: []
created: 2026-05-02
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-02 — Full-repo Review

## Resolved in 2026-03-31 Review Session

| ID | Title | Area | Type | Status | What Changed |
|----|-------|------|------|--------|-------------|
| F01 | Missing `toast` import in chat/page.tsx | web/chat | bug | auto-fixed | Added `import { toast } from 'sonner'` — was causing runtime error on conversation load failure |
| F02 | Missing `Link` import in calendar/page.tsx | web/calendar | bug | auto-fixed | Added `import { Link } from 'react-router'` — was causing runtime error when calendar rendered |

---

---
id: 0020
title: "PAR-F1 — to=\"/forgot-password\" is a dead link — no such route. Low priority (auth is OTP/Google-primary; email"
status: open
priority: P4
tags: [web, code-review-backlog]
files: [apps/web/app/routes.ts]
created: 2026-06-13
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Web → Native parity — deferred sub-items (2026-06-13)

| ID | Area | Where | Problem | Suggested fix |
|----|------|-------|---------|---------------|
| PAR-F1 | Auth | `apps/web/app/(auth)/todus/login/page.tsx:384`, `apps/web/app/routes.ts` | `to="/forgot-password"` is a **dead link** — no such route. Low priority (auth is OTP/Google-primary; email/password sign-in UI is commented out). | Either build `/forgot-password` + `/reset-password` pages (Better Auth `requestPasswordReset`/`resetPassword`) or remove the link. |

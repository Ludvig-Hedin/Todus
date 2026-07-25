---
id: 0087
title: "Move to folder — Add a \"Move to…\" context-menu submenu listing folders; add EmailService.move(ids:toFolder:) c"
status: open
priority: P3
tags: [macos, qa, code-review-backlog]
files: []
created: 2026-05-28
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-28 — macOS QA deferred features (found, not yet fixed) → Deferred — net-new feature

| Area | Where | Severity | Problem | Suggested fix |
|------|-------|----------|---------|---------------|
| Move to folder | `MacEmailInboxView` / `MacEmailThreadView` context menus + `EmailService`; backend `mail.modifyLabels` already exists | 🟡 medium | No UI to move/label a thread — only Archive (→archive) and Delete (→bin) exist. | Add a "Move to…" context-menu submenu listing folders; add `EmailService.move(ids:toFolder:)` calling `mail.modifyLabels` with a folder→label-id mapping; optimistic apply + rollback like the other actions. |

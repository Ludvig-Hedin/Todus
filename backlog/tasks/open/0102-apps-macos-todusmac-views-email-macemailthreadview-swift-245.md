---
id: 0102
title: "apps/macos/TodusMac/Views/Email/MacEmailThreadView.swift:245-262 — Compose sheet renders empty content if deta"
status: open
priority: P3
tags: [macos, bug-hunt, code-review, code-review-backlog]
files: []
created: 2026-05-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-20 — Bug Hunt: macOS app main user flows → Needs human review (3)

| File:line | Severity | Problem | Suggested fix |
|-----------|----------|---------|---------------|
| `apps/macos/TodusMac/Views/Email/MacEmailThreadView.swift:245-262` | warning | Compose sheet renders empty content if `detail?.messages.last` is nil when `showCompose=true`. User can trigger an empty 520x380 sheet. | Guard `showCompose = true` behind a `detail?.messages.last != nil` precondition, or add a placeholder/error state inside the sheet. |

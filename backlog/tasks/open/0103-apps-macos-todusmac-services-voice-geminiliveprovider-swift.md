---
id: 0103
title: "apps/macos/TodusMac/Services/Voice/GeminiLiveProvider.swift:271-279 — Captures let task = self.webSocketTask a"
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
| `apps/macos/TodusMac/Services/Voice/GeminiLiveProvider.swift:271-279` | info | Captures `let task = self.webSocketTask` at 271 but then dereferences `self.webSocketTask` again at 273 and 278 before nilling. Single-actor so unlikely race, but inconsistent. | Use the captured `task` reference throughout, then nil `self.webSocketTask` once. |

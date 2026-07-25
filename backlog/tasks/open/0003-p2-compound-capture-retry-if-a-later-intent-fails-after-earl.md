---
id: 0003
title: "P2 — compound capture retry: if a later intent fails after earlier intents have persisted, retrying"
status: open
priority: P2
tags: [code-review, code-review-backlog]
files: []
created: 2026-07-24
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Release review follow-up — 2026-07-24

- **P2 — compound capture retry:** if a later intent fails after earlier intents have persisted, retrying the retained full draft can duplicate the completed prefix. Track completed intents or stage task-only compounds atomically.

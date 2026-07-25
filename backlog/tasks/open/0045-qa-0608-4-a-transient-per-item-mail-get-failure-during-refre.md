---
id: 0045
title: "QA-0608-4 — A transient per-item mail.get failure during refresh drops that thread from the enriched set, and"
status: open
priority: P3
tags: [macos, qa, code-review-backlog]
files: []
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-08 — QA pass (macOS app, pre-TestFlight) → Needs attention (not auto-fixed — verified real, deferred as higher-risk/product calls)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| QA-0608-4 | macOS email | `EmailService.swift:561` (`assembleThreads`) + `:443` (cache write) | 🟡 med | A transient per-item `mail.get` failure during refresh drops that thread from the enriched set, and the refresh overwrites the folder cache with the smaller set → threads **vanish** until a later clean refresh. | On enrichment failure, keep the prior cached `EmailThread` for that id (merge by id) instead of evicting it. |

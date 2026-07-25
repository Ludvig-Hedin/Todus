---
id: 0043
title: "QA-0608-2 — Compose sheet binds to detail?.messages.last; opening reply/forward before the thread finishes loa"
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
| QA-0608-2 | macOS email | `MacEmailThreadView.swift:270` (reply/forward sheet) | 🟡 med | Compose sheet binds to `detail?.messages.last`; opening reply/forward before the thread finishes loading shows an empty sheet, and per-message "Reply" (`:637`) discards which message was clicked → always quotes the last message. | Capture a `@State selectedComposeMessage` when the action fires (default `detail?.latest`); guard the sheet so it can't open with no message. |

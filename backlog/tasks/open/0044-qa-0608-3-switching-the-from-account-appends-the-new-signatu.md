---
id: 0044
title: "QA-0608-3 — Switching the From account appends the new signature without stripping the old (comment claims it"
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
| QA-0608-3 | macOS email | `MacEmailComposeView.swift:916` (`appendSignatureIfNeeded`) + `:515` ("Start fresh") | 🟡 med | Switching the From account appends the new signature without stripping the old (comment claims it strips) → multi-account users stack two signatures; "Start fresh" leaves `didApplySignature = true` so the fresh draft gets no signature. | Track the last-applied signature block and strip it before re-appending; reset `didApplySignature = false` in "Start fresh" then re-seed. |

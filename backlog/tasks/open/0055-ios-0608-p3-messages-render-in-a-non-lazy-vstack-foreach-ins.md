---
id: 0055
title: "IOS-0608-P3 — Messages render in a non-lazy VStack ForEach inside a ScrollView; every expanded MessageRow owns"
status: open
priority: P3
tags: [ios, server, qa, code-review-backlog]
files: []
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-08 — iOS Simulator QA pass → Still open (verified real, deferred — higher-risk / product call / needs backend)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| IOS-0608-P3 | Email perf | `EmailThreadView.swift:~788` (`messagesSection`) | 🟡 med | Messages render in a non-lazy `VStack` ForEach inside a ScrollView; every expanded MessageRow owns a WKWebView, all built eagerly for long threads. | `LazyVStack` so off-screen rows/WebViews defer (verify scroll anchoring). |

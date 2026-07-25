---
id: 0048
title: "QA-0608-7 — No auto-advance: a user who signed in with Google already has a Gmail connection but is still show"
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
| QA-0608-7 | macOS onboarding | `MacOnboardingViews.swift:84` (`MacGmailOnboardingView`) | 🟡 med (UX) | No auto-advance: a user who signed in **with Google** already has a Gmail connection but is still shown "Connect Gmail" and re-OAuth'd if they click it. | Add `.task { await emailService.checkConnection(force:true); if hasConnection { hasConfiguredGmailPrompt = true } }` (mirrors iOS). |

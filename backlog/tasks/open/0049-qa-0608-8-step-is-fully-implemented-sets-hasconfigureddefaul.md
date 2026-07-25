---
id: 0049
title: "QA-0608-8 — Step is fully implemented (sets hasConfiguredDefaultMailPrompt) but never presented — no gate bran"
status: open
priority: P4
tags: [macos, qa, code-review-backlog]
files: []
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-08 — QA pass (macOS app, pre-TestFlight) → Needs attention (not auto-fixed — verified real, deferred as higher-risk/product calls)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| QA-0608-8 | macOS onboarding | `MacOnboardingViews.swift:508` (`MacDefaultMailOnboardingView`) | 🔵 low | Step is fully implemented (sets `hasConfiguredDefaultMailPrompt`) but never presented — no gate branch in `MacRootView` onboarding chain. Dead/half-wired step. | Either delete it + its flag plumbing, or add the gate branch and bump `onboardingTotalSteps`. |

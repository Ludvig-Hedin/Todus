---
id: 0071
title: "BH-0605-10 — \"Used X of Y credits\" can show used > limit when over quota (only aiUsagePercent is clamped) — co"
status: open
priority: P4
tags: [ios, macos, bug-hunt, code-review-backlog]
files: []
created: 2026-06-05
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-05 — Bug hunt (iOS + macOS changed files) → Needs attention (not auto-fixed — TODO added in code where noted)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| BH-0605-10 | iOS billing | `BillingSettingsView.swift:235` | 🔵 low | "Used X of Y credits" can show used > limit when over quota (only `aiUsagePercent` is clamped) — contradicts the clamped "0% remaining". | Product decision: clamp displayed used to limit, or accept true overage display. |

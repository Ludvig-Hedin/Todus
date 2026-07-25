---
id: 0076
title: "BH-0601b-3 — Same sender renders at 40pt in the inbox list but 36pt in thread detail (MessageRow). Avatar visi"
status: open
priority: P4
tags: [ios, bug-hunt, code-review-backlog]
files: []
created: 2026-06-01
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-01 — Bug hunt (iOS screenshots: bg color / alignment / thread-load) → Needs attention (not auto-fixed)

| ID | Area | Where | Severity | Problem | Suggested fix |
|----|------|-------|----------|---------|---------------|
| BH-0601b-3 | iOS thread | `EmailThreadView.swift:1655` vs `EmailRowView.swift:29` | 🔵 low | Same sender renders at 40pt in the inbox list but 36pt in thread detail (`MessageRow`). Avatar visibly shrinks on open. Internally consistent within the thread (the divider inset `16+36+10` matches 36), so likely intentional. | Pick one diameter for both, or leave as documented-intentional. |

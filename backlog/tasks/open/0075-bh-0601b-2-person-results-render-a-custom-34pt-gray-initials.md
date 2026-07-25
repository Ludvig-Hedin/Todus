---
id: 0075
title: "BH-0601b-2 — Person results render a custom 34pt gray-initials ZStack, while the inbox People tab uses 40pt Se"
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
| BH-0601b-2 | iOS search | `apps/ios/Todus/Todus/Features/Search/GlobalSearchView.swift:342-351` (`personRow`) | 🔵 low | Person results render a custom 34pt gray-initials ZStack, while the inbox People tab uses 40pt `SenderAvatarView` (real photos / brand logos). Same person shows different size + no real avatar in search. | Replace the ZStack with `SenderAvatarView(email:name:size: 40)` for parity. (Behavior change: adds network avatar resolution to search rows — deferred, out of stated scope.) |

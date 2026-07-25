---
id: 0025
title: "MAC-2 — Message list is an eager VStack (not LazyVStack); WebViews are gated by isExpanded so open cost is bou"
status: open
priority: P3
tags: [macos, code-review, qa, code-review-backlog]
files: [Views/Email/MacEmailThreadView.swift]
created: 2026-06-13
source: CODE_REVIEW_BACKLOG.md
---

> Source context: macOS QA pass — 2026-06-13 — email loading / thread-open / hangs → Needs human review (deferred)

| ID | Area | Where | Sev | Problem | Suggested fix |
|----|------|-------|-----|---------|---------------|
| MAC-2 | Email perf | `Views/Email/MacEmailThreadView.swift` `messageView` `ForEach` | 🟡 med | Message list is an eager `VStack` (not `LazyVStack`); WebViews are gated by `isExpanded` so open cost is bounded today, but very long threads with several expanded messages build multiple `WKWebView`s on the main thread. | Lazy-mount + pool WebViews if long-thread jank shows up in profiling. |

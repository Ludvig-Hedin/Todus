---
id: 0105
title: "001 — home/page.tsx defines its own inline TaskItem component instead of importing the shared components/tasks"
status: open
priority: P4
tags: [macos, bug-hunt, code-review-backlog]
files: [home/page.tsx, components/tasks/task-item.tsx]
created: 2026-05-20
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-20 — Bug Hunt: macOS app main user flows → Open Items

| ID | Title | Area | Type | Impact | Risk | Status | Summary |
|----|-------|------|------|--------|------|--------|---------|
| 001 | Inline TaskItem duplicated in home/page.tsx | web/home | design-debt | internal | low | open | `home/page.tsx` defines its own inline `TaskItem` component instead of importing the shared `components/tasks/task-item.tsx`. Both work correctly but will diverge over time. Fix: import from `@/components/tasks/task-item` and remove the inline definition. |

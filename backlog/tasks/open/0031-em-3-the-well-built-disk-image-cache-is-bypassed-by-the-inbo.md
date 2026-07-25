---
id: 0031
title: "EM-3 — The well-built disk image cache is bypassed by the inbox (only 2 settings avatars use it); inbox relies"
status: open
priority: P2
tags: [ios, bug-hunt, code-review, code-review-backlog]
files: [AppTheme.swift]
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Bug Hunt — 2026-06-08 — iOS email surface (`/bug-hunt`) → Needs human review (verified real, deferred — higher-risk / unvalidatable under `--ui-testing` / product calls)

| ID | Area | Where | Sev | Problem | Suggested fix |
|----|------|-------|-----|---------|---------------|
| EM-3 | Email perf | `SenderAvatarView.swift:548` vs `AppTheme.swift` `AvatarDiskCache`/`CachedAvatarImage` | 🟠 high | The well-built **disk image cache is bypassed** by the inbox (only 2 settings avatars use it); inbox relies on `URLCache`, which 3rd-party favicon providers don't always make cacheable → refetch each launch. | Route sender avatars through the disk cache. |

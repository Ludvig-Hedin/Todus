---
id: 0029
title: "EM-1 — Inbox avatars use raw AsyncImage with no downsampling — 256–512px favicons/apple-touch-icons decoded fu"
status: open
priority: P2
tags: [ios, bug-hunt, code-review, code-review-backlog]
files: []
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Bug Hunt — 2026-06-08 — iOS email surface (`/bug-hunt`) → Needs human review (verified real, deferred — higher-risk / unvalidatable under `--ui-testing` / product calls)

| ID | Area | Where | Sev | Problem | Suggested fix |
|----|------|-------|-----|---------|---------------|
| EM-1 | Email perf | `SenderAvatarView.swift:548` | 🟠 high | Inbox avatars use raw `AsyncImage` with **no downsampling** — 256–512px favicons/apple-touch-icons decoded full-size into a 40pt circle; main memory/CPU cost on fast scroll. | ImageIO thumbnail decode; route through the existing `CachedAvatarImage`. |

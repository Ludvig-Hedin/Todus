---
id: 0190
title: "PERF-5 — Resolved 2026-07-23 — centralized Sendable boxing/data helpers persist off-main across Create, task d"
status: done
tags: [ios, performance, code-review-backlog]
files: [Services/Tasks/AttachmentService.swift]
created: 2026-07-11
source: CODE_REVIEW_BACKLOG.md
---

> Source context: iOS performance pass — deferred findings, 2026-07-11

| ID | File | Issue | Fix direction | Why deferred |
|----|------|-------|---------------|--------------|
| ~~PERF-5~~ | `Services/Tasks/AttachmentService.swift` + attachment views | ~~JPEG encoding and disk writes blocked camera, picker, and paste callbacks~~ | **Resolved 2026-07-23** — centralized Sendable boxing/data helpers persist off-main across Create, task detail, AI chat, and mail compose | — |

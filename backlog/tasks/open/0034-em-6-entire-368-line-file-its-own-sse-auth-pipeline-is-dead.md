---
id: 0034
title: "EM-6 — Entire 368-line file (its own SSE/auth pipeline) is dead — never instantiated; compose aiFAB opens AICh"
status: open
priority: P2
tags: [ios, bug-hunt, code-review, code-review-backlog]
files: [Features/Email/EmailAIDraftSheet.swift]
created: 2026-06-08
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Bug Hunt — 2026-06-08 — iOS email surface (`/bug-hunt`) → Needs human review (verified real, deferred — higher-risk / unvalidatable under `--ui-testing` / product calls)

| ID | Area | Where | Sev | Problem | Suggested fix |
|----|------|-------|-----|---------|---------------|
| EM-6 | Email | `Features/Email/EmailAIDraftSheet.swift` | 🟠 high | Entire 368-line file (its own SSE/auth pipeline) is **dead** — never instantiated; compose `aiFAB` opens `AIChatView`. | Delete the file (requires removing it from `Todus.xcodeproj` — do via Xcode). |

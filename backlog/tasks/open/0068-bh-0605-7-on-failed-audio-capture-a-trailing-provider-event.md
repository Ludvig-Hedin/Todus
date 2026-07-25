---
id: 0068
title: "BH-0605-7 — On failed audio capture, a trailing provider event between consumer-cancel and provider.disconnect"
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
| BH-0605-7 | iOS voice | `VoiceChatViewModel.swift:132` (TODO) | 🔵 low | On failed audio capture, a trailing provider event between consumer-cancel and `provider.disconnect()` can overwrite `.failed`, resurrecting a dead session. | Ignore events once `connectionState == .failed`, or re-assert `.failed` after `disconnect()` returns. |

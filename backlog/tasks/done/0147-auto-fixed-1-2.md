---
id: 0147
title: "Auto-fixed (1)"
status: done
tags: [ios, bug-hunt, code-review-backlog]
files: []
created: 2026-06-01
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-06-01 — Bug hunt (iOS screenshots: bg color / alignment / thread-load)

## Auto-fixed (1)

| File:line | Severity | What changed |
|-----------|----------|--------------|
| `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift:~1196` (loadingState skeleton) | 🟡 medium (visible) | Skeleton row geometry didn't match the real row, so every cold inbox load "jumped" when the skeleton swapped to content. Skeleton was `HStack(spacing: 12)` + 36×36 avatar + `vpad 12`; `EmailRowView` is `spacing 10` + 40×40 (`SenderAvatarView` default) + `vpad 11`. Matched the skeleton to the real row (10 / 40 / 11). Pure placeholder geometry — no logic touched. |

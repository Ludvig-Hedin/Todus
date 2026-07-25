---
id: 0088
title: "Compose-card CC/BCC input — CC/BCC rows render existing recipients but provide no field to add any — addRecipi"
status: open
priority: P3
tags: [macos, qa, code-review-backlog]
files: [Views/AI/ChatUISpec/CardViews.swift]
created: 2026-05-28
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-28 — macOS QA deferred features (found, not yet fixed) → Deferred — net-new feature

| Area | Where | Severity | Problem | Suggested fix |
|------|-------|----------|---------|---------------|
| Compose-card CC/BCC input | `Views/AI/ChatUISpec/CardViews.swift` `MacInlineComposeCardView` (CC/BCC rows ~630–649) | 🟡 medium | CC/BCC rows render existing recipients but provide no field to add any — `addRecipient(target:)` is only ever called with `"to"`, so the `cc`/`bcc` branches are dead. | Add `TextField`s bound to per-field input (or a target selector) calling `addRecipient(target: "cc" / "bcc")`. |

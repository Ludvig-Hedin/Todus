---
id: 0085
title: "Email attachment download — Add a backend attachment-fetch endpoint (mail.getAttachment), then wire tap → down"
status: open
priority: P3
tags: [macos, server, qa, code-review-backlog]
files: []
created: 2026-05-28
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-28 — macOS QA deferred features (found, not yet fixed) → Deferred — needs backend

| Area | Where | Severity | Problem | Suggested fix |
|------|-------|----------|---------|---------------|
| Email attachment download | `MacEmailThreadView.attachmentsView` (chips are display-only) | 🟡 medium | Attachment chips now render (filename/type/size) but tapping does nothing — there's no fetch/download. | Add a backend attachment-fetch endpoint (`mail.getAttachment`), then wire tap → download/save to disk + open. |

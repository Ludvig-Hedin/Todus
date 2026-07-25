---
id: 0084
title: "iOS markdown email send — macOS now converts the compose markdown body → HTML before send (commit ed8eb057), b"
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
| iOS markdown email send | `apps/ios/Todus/Todus/Services/Email/EmailService` send path | 🟡 medium | macOS now converts the compose markdown body → HTML before send (commit `ed8eb057`), but iOS still sends raw markdown wrapped as `text/html`, so recipients see literal `**bold**` / `# heading` and the body collapses onto one line. | Share the `EmailBodyHTML.render` converter cross-platform (move to `packages/shared` or convert once on the backend) and apply it in the iOS send path too. |

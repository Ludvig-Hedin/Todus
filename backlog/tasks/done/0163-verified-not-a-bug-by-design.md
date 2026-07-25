---
id: 0163
title: "Verified NOT-A-BUG / by-design"
status: done
tags: [code-review-backlog]
files: []
created: 2026-06-13
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Backlog resolution pass — 2026-06-13 (whole-repo)

## Verified NOT-A-BUG / by-design

- Server: B-026 (`lastReviewedAt` column doesn't exist on `assistant_prepared_action`), B-017 (`WorkflowRunner` is a DurableObject, not a CF Workflow — no replay).
- iOS: EM-9 (navigationDestination(item:) auto-resets on dismiss), B-018 (`@MainActor` class is implicitly Sendable).
- macOS: QA-0608-6 (picker intentionally editable), B-032 (bucket vs score split is display-only).
- Web: PAR-B3 (mention context IS injected into the agent input, not UI-only).

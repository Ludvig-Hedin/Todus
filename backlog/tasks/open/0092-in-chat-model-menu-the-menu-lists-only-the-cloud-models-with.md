---
id: 0092
title: "In-chat model menu — The menu lists only the cloud models with a checkmark; a local model selected from Settin"
status: open
priority: P4
tags: [macos, qa, code-review-backlog]
files: []
created: 2026-05-28
source: CODE_REVIEW_BACKLOG.md
---

> Source context: 2026-05-28 — macOS QA deferred features (found, not yet fixed) → Deferred — medium / low (client, but untestable here)

| Area | Where | Severity | Problem | Suggested fix |
|------|-------|----------|---------|---------------|
| In-chat model menu | `MacAssistantPanel` model menu (~1738) | 🔵 low | The menu lists only the cloud models with a checkmark; a local model selected from Settings shows no checkmark/indicator and can't be seen/switched from chat. | Surface the active local model (name + checkmark) in the menu, or a "Local: <name>" row. |

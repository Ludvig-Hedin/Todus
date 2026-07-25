---
id: 0258
title: "DONE AI billing unlimited-state + sidebar image-only submit (2026-04): Server billing cache now pres"
status: done
tags: [task-md, sprint]
files: []
created: unknown
source: TASK.md
---

> Source context: TASK.md → Current Native Fix Batch

- `DONE` **AI billing unlimited-state + sidebar image-only submit (2026-04):** Server billing cache now preserves Autumn `ai_usage.unlimited` and exposes `aiUsage.unlimited` to clients, so unlimited plans no longer get blocked by text/voice/agent AI pre-flight checks. The mail sidebar AI composer now submits pasted-image-only turns through `append(..., { allowEmptySubmit: true })`, preventing silent drops and lost pending images. iOS/macOS/web billing surfaces now render unlimited AI usage explicitly instead of showing a zero-credit exhausted state.

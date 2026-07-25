---
id: 0257
title: "Fix — Closed review-found regressions in AI billing and legacy schema compatibility by hydrating legacy billin"
status: archived
category: Fixed
release_date: 2026-04-25
source: CHANGELOG.md
---

[2026-04-25] [Fix] Closed review-found regressions in AI billing and legacy schema compatibility by hydrating legacy billing state on AI access, billing chat/search usage against the concrete resolved model, and restoring legacy `mail0_connection` fallback reads inside the Zero chat agent. Architectural safety fix. (`apps/server/src/lib/ai-model-resolver.ts`, `apps/server/src/lib/billing.ts`, `apps/server/src/routes/chat.ts`).

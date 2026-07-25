---
id: 0202
title: "Refactor — Adopt centralized AI model resolver across backend"
status: archived
category: Changed
release_date: 2026-04-08
source: CHANGELOG.md
---

## [2026-04-08] Refactor — Adopt centralized AI model resolver across backend

- [Refactor] Replaced direct `openai(...)` model construction calls with the centralized `resolveModel()` / `resolveModelFromSettings()` from `ai-model-resolver.ts` in five backend files.
- [Refactor] `search.ts` uses `resolveModelFromSettings()` since it already loads user settings, enabling per-user provider selection.
- [Refactor] `compose.ts`, `interests.ts`, `groups.ts`, and `meet.ts` use `resolveModel({ provider: 'auto', ... })` which preserves the existing env-var cascade (OpenRouter -> Google -> OpenAI -> Anthropic).
- **Files:** `apps/server/src/trpc/routes/ai/compose.ts`, `apps/server/src/trpc/routes/ai/search.ts`, `apps/server/src/lib/analyze/interests.ts`, `apps/server/src/trpc/routes/groups.ts`, `apps/server/src/trpc/routes/meet.ts`

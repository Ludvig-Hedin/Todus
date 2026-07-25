---
id: 0201
title: "Feature — Ollama integration + AI model selector"
status: archived
category: Added
release_date: 2026-04-08
source: CHANGELOG.md
---

## [2026-04-08] Feature — Ollama integration + AI model selector

- [Feature] Added user-facing AI provider/model selector in the chat sidebar header (compact) and a full AI settings page at `/settings/ai`.
- [Feature] Users can now select from OpenAI, Anthropic, Google, Groq, OpenRouter, or Ollama (local) as their AI provider.
- [Feature] Ollama integration: list installed models, pull new models with progress, delete models, connection status indicator, CORS troubleshooting help.
- [Feature] Added `aiProvider`, `aiModel`, and `ollamaBaseUrl` to user settings schema.
- [Refactor] Created centralized `ai-model-resolver.ts` — single source of truth for model construction across all backend endpoints.
- [Refactor] Replaced hardcoded `openai(...)` calls in 10+ backend files with the resolver.
- [UI] New settings nav item "AI & Models" with Cpu icon.
- **New files:** `ai-model-resolver.ts`, `model-selector.tsx`, `use-ollama.ts`, `ollama-utils.ts`, `settings/ai/page.tsx`
- **Modified files:** `schemas.ts`, `agent/index.ts`, `ai-sidebar.tsx`, `ai-chat.tsx`, `routes.ts`, `navigation.ts`, `compose.ts`, `search.ts`, `chat.ts`, `ai.ts`, `tools.ts`, `interests.ts`, `groups.ts`, `meet.ts`

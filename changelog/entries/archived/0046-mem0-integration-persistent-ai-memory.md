---
id: 0046
title: "Mem0 Integration — Persistent AI Memory"
status: archived
category: Changed
release_date: 2026-03-27
source: CHANGELOG.md
---

## [2026-03-27] Mem0 Integration — Persistent AI Memory

### New Feature

- **`apps/server/src/lib/mem0.ts`** (NEW): Mem0 REST API client with multi-layer caching (in-memory → KV → API). Provides `addMemories`, `searchMemories`, `getAllMemories`, `getCachedMemories`, `preloadMemories`, `invalidateMemoryCache`, and `formatMemoriesForPrompt`.
- **`apps/server/src/env.ts`**: Added `MEM0_API_KEY` to `ZeroEnv` type. Set via Cloudflare dashboard secrets.
- **`apps/server/src/routes/ai.ts`**: Integrated Mem0 into `/ai/chat` (iOS flow). Injects cached memories into system prompt. Captures assistant response via TransformStream tee and stores conversation in Mem0 post-stream.
- **`apps/server/src/routes/agent/index.ts`**: Integrated Mem0 into ZeroAgent (web flow). Preloads memories on WebSocket connect (background). Injects cached memories into system prompt (0ms). Stores conversation in Mem0 after response (fire-and-forget).

### Architecture

- **Zero latency**: Memories are preloaded on WebSocket connect / KV-cached. Hot path reads are 0ms (in-memory) or <5ms (KV). No Mem0 API calls block the user.
- **Cross-platform**: Both web and iOS share the same `user_id` (Better Auth user.id), so memories cross-pollinate.
- **Graceful degradation**: All Mem0 calls are try/catch wrapped. If Mem0 is down or unconfigured, AI works normally without memory.
- **No iOS changes needed**: Backend handles all Mem0 integration server-side.

### Setup Required

- Add `MEM0_API_KEY` as a Cloudflare secret (dashboard) and in `.env` for local dev.
- Sign up at https://app.mem0.ai to get an API key.

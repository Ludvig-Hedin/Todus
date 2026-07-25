---
id: 0262
title: "Fix — native AI chat stream bootstrap + assistant fallback hardening"
status: archived
category: Fixed
release_date: 2026-04-26
source: CHANGELOG.md
---

## [2026-04-26] Fix — native AI chat stream bootstrap + assistant fallback hardening

- [Fix] **iOS AI chat no longer waits for the provider before the SSE stream opens.** `/api/ai/chat` now returns the SSE response immediately, emits an initial bootstrap event, and only then waits on OpenRouter/Gemini. This prevents native clients from timing out during long tool-planning/model-startup delays that previously ended as `Connection lost — tap to retry.`
- [Fix] **Provider failures now surface as chat errors instead of a silent dropped stream.** If OpenRouter/Gemini rejects or fails before streaming content, the server emits an `error` SSE event and iOS renders that as an assistant error message.
- [Fix] **Assistant briefing now degrades on shard-pool saturation.** `assistant.getBriefing` treats shard initialization / Postgres pool-slot exhaustion as a degraded-but-recoverable condition and returns the lightweight fallback briefing instead of bubbling a 500 into Home startup.
- [Fix] **Native chat streams now tolerate slower first-token latency.** iOS sets an explicit 180-second timeout for `/api/ai/chat` streaming requests, reducing false client-side `NSURLErrorDomain -1001` failures while the backend/tool chain is still working.
- [Files] `apps/server/src/routes/ai.ts`, `apps/server/src/trpc/routes/assistant.ts`, `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`, `CHANGELOG.md`, `TASK.md`

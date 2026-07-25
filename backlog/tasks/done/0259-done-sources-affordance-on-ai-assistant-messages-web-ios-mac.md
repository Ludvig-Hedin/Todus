---
id: 0259
title: "DONE Sources affordance on AI assistant messages (web + iOS + macOS, 2026-04): Backend now emits a u"
status: done
tags: [task-md, sprint]
files: [apps/server/src/lib/ai-sources.ts, apps/server/src/routes/ai.ts, apps/ios/Todus/Todus/Features/AI/AISourcesView.swift, apps/mail/components/create/ai-sources.tsx, ai-chat.tsx, BrandIcons.swift]
created: unknown
source: TASK.md
---

> Source context: TASK.md → Current Native Fix Batch

- `DONE` **Sources affordance on AI assistant messages (web + iOS + macOS, 2026-04):** Backend now emits a unified `context_sources` SSE event aggregating web search, resolved `@`mentions, and Mem0 memories (`apps/server/src/lib/ai-sources.ts`, `apps/server/src/routes/ai.ts`). iOS replaced the legacy horizontal web-source chips with a stacked-icons "Sources" button inline with the assistant action row that opens a list sheet (`apps/ios/Todus/Todus/Features/AI/AISourcesView.swift`); tool-call results from `executeSingleToolCall` are appended client-side. macOS added `MacAISourcesView` + a parallel `contextSources` field on `MacChatMessage`. Web added a self-contained `<Sources />` component (`apps/mail/components/create/ai-sources.tsx`) ready for the AI-SDK SSE listener wiring inside `ai-chat.tsx`. New brand icons (Meet / Notes / Document / Todus chat / Memory / Company / Website) added to `BrandIcons.swift`.

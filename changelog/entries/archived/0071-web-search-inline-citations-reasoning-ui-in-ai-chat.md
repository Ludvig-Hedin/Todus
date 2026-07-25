---
id: 0071
title: "Web Search + Inline Citations + Reasoning UI in AI Chat"
status: archived
category: Changed
release_date: 2026-03-28
source: CHANGELOG.md
---

## [2026-03-28] Web Search + Inline Citations + Reasoning UI in AI Chat

### Summary

Full ChatGPT/Perplexity-style search + reasoning UX in the AI chat. When a user asks a factual question, the backend searches the web via Perplexity, streams sources as custom SSE events, and the iOS app renders a "Searching the web…" indicator, source pills, tappable citation superscripts, and a collapsible reasoning box. Reasoning models (deepseek-r1, o1, etc.) get a dedicated thinking UI with auto-collapse.

### Backend (`apps/server/src/routes/ai.ts`)

- Added `shouldSearchWeb()` heuristic to detect queries needing web information
- Added `performWebSearch()` — Tavily primary (pure search API, 1k free/mo, real snippets), Perplexity sonar fallback (no SDK needed — raw `fetch` for both). Gracefully returns empty if neither key is configured.
- Added `injectSearchContext()` to format sources + citation instructions into the LLM prompt
- Modified `/ai/chat` SSE stream to write custom events (`search_status`, `sources`) before piping OpenRouter response
- Refactored response stream from TransformStream passthrough to ReadableStream with explicit writer (supports pre-stream custom events while preserving Mem0 capture)
- Added `TAVILY_API_KEY` to `env.ts` type definitions

### iOS Model (`AIChatMessage.swift`)

- Added `WebSource` struct (url, title, snippet, domain computed property)
- Extended `AIChatMessage` with: `sources`, `searchQueries`, `searchState` (SearchPhase enum), `reasoningContent`, `reasoningDurationMs`

### iOS Service (`AIChatService.swift`)

- Added `SSECustomEvent` and `SSESourcePayload` decode structs
- Modified SSE parsing loop to try custom event decode before OpenRouter chunk decode (backward compatible)
- Added `handleCustomEvent()` method to update message search/source/reasoning state

### iOS UI (`AIChatView.swift`)

- Added `SearchingIndicator` view: spinning globe + "Searching the web…" + query text
- Added `SourceChipsView`: horizontal ScrollView of capsule pills with favicon + domain, tappable to open URL
- Modified `assistantBubble` to render search indicator and source chips above the answer content
- Added scroll-to-bottom trigger when sources arrive

### V2 Additions (same session)

**Backend:**

- Improved `shouldSearchWeb()` heuristic: skips task/email/calendar commands, filters short messages, two-tier check (time-sensitive vs factual questions vs own-data queries)
- Added reasoning token extraction from OpenRouter SSE (`delta.reasoning_content` / `delta.reasoning`) for reasoning models (deepseek-r1, o1, o3-mini)
- Re-emits reasoning tokens as custom `reasoning` events + `reasoning_done` with duration

**iOS UI:**

- `ReasoningBox`: collapsible thinking/reasoning box with pulsing brain icon, auto-expands while streaming, auto-collapses 0.8s after completion, tap header to toggle, shows "Thought for Xs"
- `SourceDetailSheet`: tap any source chip to expand a detail sheet with full title, domain, snippet, and "Open in Safari" button. Long-press for context menu (open in Safari, copy URL)
- Source chips now show citation number badges `[1]`, `[2]` alongside favicon + domain
- `styleCitations()`: post-processes AttributedString to highlight `[n]` patterns as blue superscript text, linked to source URLs (works in both inline streaming and full markdown modes)
- Citation links open directly in Safari when tapped

### Architecture Decision

- Single SSE stream with custom event types (backward compatible — old clients silently skip unknown JSON)
- Backend-orchestrated search (client doesn't need to know about search providers)
- Smart heuristic search trigger with command filtering (skips task/email/calendar ops)

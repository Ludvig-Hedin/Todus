---
id: 0080
title: "Fix — Buffer early WebSocket messages in voice proxy"
status: archived
category: Fixed
release_date: 2026-03-29
source: CHANGELOG.md
---

## [2026-03-29] Fix — Buffer early WebSocket messages in voice proxy

### Summary

In the `/ai/voice-ws` WebSocket proxy, `serverWs.accept()` was called before the upstream Gemini connection was established and forwarding handlers attached. Any client messages arriving during the Gemini `fetch()` would be silently dropped (e.g. the setup config message). Added an early-buffering message handler that queues messages until upstream is ready, then flushes them in order before switching to direct forwarding.

**Files changed:**

- `apps/server/src/routes/ai.ts` — Attach buffering handler immediately after `serverWs.accept()`, flush + switch to direct forwarding after `upstream.accept()`

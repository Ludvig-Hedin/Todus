---
id: 0171
title: "PAR-C — ✅ CODE DONE — callServerTool bridge (lib/server-tool.ts → POST /api/ai/do/:action) + clientTools re-en"
status: done
tags: [web, code-review-backlog]
files: [apps/web/providers/voice-provider.tsx, apps/web/lib/server-tool.ts, lib/server-tool.ts, voice-provider.tsx]
created: 2026-06-13
source: CODE_REVIEW_BACKLOG.md
---

> Source context: Web → Native parity — deferred sub-items (2026-06-13)

| ID | Area | Where | Problem | Suggested fix |
|----|------|-------|---------|---------------|
| ~~PAR-C~~ | Voice tools | `apps/web/providers/voice-provider.tsx`, `apps/web/lib/server-tool.ts` | ✅ CODE DONE — `callServerTool` bridge (`lib/server-tool.ts` → `POST /api/ai/do/:action`) + `clientTools` re-enabled in `voice-provider.tsx`, tsc-clean, errors caught (no throw on a normal session). The only residual is the **external ElevenLabs dashboard** tool-declaration + `VITE_PUBLIC_ELEVENLABS_AGENT_ID` — an operator/deployment step, not a code defect (see "Operator / deployment prerequisites" above). | — |

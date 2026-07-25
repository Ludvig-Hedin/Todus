---
id: 0003
title: "Activate ElevenLabs voice client tools (dashboard + env)"
status: open
priority: P1
area: integrations
source: "CODE_REVIEW_BACKLOG.md — Operator / deployment prerequisites (2026-06-13)"
created: 2026-07-25
---

The bridge code ships and compiles (`apps/web/lib/server-tool.ts` → `POST /api/ai/do/:action`, client tools re-enabled in `voice-provider.tsx`). Voice tool-calling still does nothing until the agent itself declares the tools — that is third-party SaaS config, not a repo change.

- [ ] In the **ElevenLabs web dashboard**, open the agent used by Todus
- [ ] Declare the client tools (names + JSON schemas) that match the `/api/ai/do/:action` actions
- [ ] Set `VITE_PUBLIC_ELEVENLABS_AGENT_ID` in the **web deploy environment** (Cloudflare Workers env for `@zero/web`), not only in the local `.env`
- [ ] Start a voice session in the deployed app and confirm one tool call round-trips

No ElevenLabs credentials exist in the repo environment, so no agent can do this step.

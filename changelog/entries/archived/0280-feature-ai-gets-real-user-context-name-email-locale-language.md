---
id: 0280
title: "Feature — AI gets real user context (name, email, locale, language) + speaks the user's language"
status: archived
category: Added
release_date: 2026-04-27
source: CHANGELOG.md
---

## [2026-04-27] Feature — AI gets real user context (name, email, locale, language) + speaks the user's language

- [Feature] **`buildAIProfilePrompt`** in [`apps/server/src/lib/ai-profile.ts`](apps/server/src/lib/ai-profile.ts) was rewritten to inject four new sections into every chat system prompt: (1) **About the user** — name + email so the AI can address the user correctly and produce accurate `From:` lines in drafts; (2) **Locale** — timezone, preferred language, and the user's current local date/time computed via `Intl.DateTimeFormat` so relative references like "tomorrow" and "this evening" resolve without a clarifying question; (3) **Reply language** — explicit instruction to mirror the language of the latest user message (with tone matching) and to localize all card text shown to the user (titles, summaries, button labels, suggestion chips) while keeping stable identifiers like `action` names and IDs in English; (4) the existing user-supplied `contextAboutYou` and `customPrompt` blocks, now clearly labeled as user-provided. Falls back to identity + locale defaults if `findUserSettings` errors transiently — previously this returned an empty string and dropped name/email entirely.
- [Feature] **`getSharedAIProfilePromptForUser`** now takes an optional `{ name, email }` identity argument; both call sites in [`apps/server/src/routes/ai.ts`](apps/server/src/routes/ai.ts) (the SSE chat endpoint at line ~503 and the `generateText` follow-up at line ~1315) pass `user.name` and `user.email` from the session.
- [Privacy] The user's own name and email flow only to the LLM that's already serving that user's session — same data the assistant needs to draft outgoing mail. No third parties involved; the user consented at account creation. We deliberately do not include other users' identities in this profile block.
- [Feature] **Audit:** verified all 21 card types and 6 layout primitives (`Stack`, `Card`, `Text`, `Button`, `Badge`, `Divider`) are present and consistent across server contract → web catalog → web registry → iOS dispatch → macOS dispatch. No drift.
- [Files] `apps/server/src/lib/ai-profile.ts`, `apps/server/src/routes/ai.ts`, `CHANGELOG.md`

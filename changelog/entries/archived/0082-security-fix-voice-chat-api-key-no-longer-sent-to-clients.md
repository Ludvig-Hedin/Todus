---
id: 0082
title: "Security Fix — Voice Chat API Key No Longer Sent to Clients"
status: archived
category: Security
release_date: 2026-03-29
source: CHANGELOG.md
---

## [2026-03-29] Security Fix — Voice Chat API Key No Longer Sent to Clients

### Summary

The `POST /ai/voice-token` endpoint returned the raw `GOOGLE_GENERATIVE_AI_API_KEY` to any authenticated user. This was a credential leak — users could extract the long-lived key and call Gemini directly outside the app. The `expiresAt` field was just a client-side hint with no server enforcement.

**Fix:** Replaced the REST token endpoint with a **WebSocket proxy** (`GET /ai/voice-ws`). The backend now accepts a WebSocket upgrade from the iOS client (authenticated via the existing Bearer token), opens a separate WebSocket to Gemini with the API key server-side, and transparently forwards all messages bidirectionally. The API key never reaches the client.

**Files changed:**

- `apps/server/src/routes/ai.ts` — Replaced `POST /voice-token` with `GET /voice-ws` WebSocket proxy
- `apps/ios/Todus/Todus/Services/Voice/VoiceProvider.swift` — Protocol: `connect(token:config:)` → `connect(endpoint:authToken:config:)`
- `apps/ios/Todus/Todus/Services/Voice/GeminiLiveProvider.swift` — Connects to backend proxy URL with Authorization header instead of Gemini directly
- `apps/ios/Todus/Todus/Services/Voice/VoiceTokenService.swift` — Rewritten to build WS proxy URL from backend URL + auth token (no longer fetches API key)
- `apps/ios/Todus/Todus/Features/Voice/VoiceChatViewModel.swift` — Updated connect flow to use new `getEndpoint()` API
- `apps/ios/Todus/Todus/App/AppServices.swift` — Updated VoiceTokenService init to take `authService` + `backendURL` instead of `apiClient`

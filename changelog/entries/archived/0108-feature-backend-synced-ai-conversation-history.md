---
id: 0108
title: "Feature — Backend-synced AI conversation history"
status: archived
category: Added
release_date: 2026-03-30
source: CHANGELOG.md
---

## [2026-03-30] Feature — Backend-synced AI conversation history

Conversations now sync to the backend via tRPC, enabling cross-device and cross-reinstall persistence.

### Backend

- **New table:** `mail0_ai_conversation` (id, userId, title, messages JSONB, timestamps)
- **New tRPC endpoints:** `ai.listConversations`, `ai.getConversation`, `ai.saveConversation`, `ai.deleteConversation`
- **Migration:** `0039_brainy_junta.sql`

### iOS & macOS

- Conversations synced to backend on save/delete (fire-and-forget)
- On launch: loads local cache first, then merges with backend
- Local cache moved from UserDefaults → Keychain (survives reinstall)
- Auto-migration from old UserDefaults storage

**Files:** `apps/server/src/db/schema.ts`, `apps/server/src/trpc/routes/ai/conversations.ts`, `apps/server/src/trpc/routes/ai/index.ts`, `apps/server/src/db/migrations/0039_brainy_junta.sql`, `apps/ios/.../AIChatService.swift`, `apps/macos/.../MacAIChatService.swift`

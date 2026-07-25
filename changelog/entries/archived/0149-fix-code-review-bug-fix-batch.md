---
id: 0149
title: "Fix — Code review bug-fix batch"
status: archived
category: Fixed
release_date: 2026-04-01
source: CHANGELOG.md
---

## [2026-04-01] Fix — Code review bug-fix batch

### CHANGELOG

- Corrected "4 branches" → "5 branches" in iOS EmailInboxView entry.

### Backend (`apps/server`)

- `calendar.ts`: Added `scopeMissing: false` to non-Google early returns in `events` and `calendars` procedures so the shape is consistent.
- `settings.ts`: `save` mutation now validates existing settings through `userSettingsSchema.safeParse` before merging, eliminating the unsafe `as UserSettings` cast.
- `groups.ts`: `generateToken()` now uses URL-safe base64 (replaces `+`→`-`, `/`→`_` instead of stripping) for reliable 16-char output. `create` and `join` wrapped in transactions. `regenerateInvite` now calls `requireActiveGroup`. `listMessages` uses compound `timestamp:id` cursor. `generateGroupAIResponse` opens its own DB connection so it can run safely in a background `waitUntil` after the request connection closes.
- `sharing.ts`: Added `passwordSalt` guard in `get` and `import`. `update` now filters out revoked shares. `import` is now rate-limited. Rate-limiter comment clarified (per-IP bucketing handled by middleware).
- `mail-assistant.ts`: `listAssistantActivity` wraps `JSON.parse` in try/catch per key. `createGoogleCalendarEvent` adds `timeZone: 'UTC'` to start/end. Draft subject fallback changed from `undefined` to `'No Subject'`.
- `migrations/0041`: Removed 3 redundant B-tree indexes (`group_slug_idx`, `group_invite_token_idx`, `shared_conversation_slug_idx`) that duplicated existing UNIQUE constraints.

### Web (`apps/mail`)

- `calendar/page.tsx`: Removed redundant ternary `e.allDay ? new Date(e.startTime) : new Date(e.startTime)`.
- `mail-list.tsx`: Empty-inbox state now checks `!isConnectionLoading` to prevent flash before connection loads.
- `settings/sharing/page.tsx`: Added `'use client'` directive; clipboard `writeText` now properly awaited with error toast fallback.
- `group-chat-view.tsx`: `handleSend` restores message text on mutation error; `copyInviteLink` awaits clipboard with error toast.
- `share-conversation-modal.tsx`: `handleCopy` awaits clipboard with error toast; success message is conditional on visibility.
- `group-join/[token]/page.tsx`: Added `onError` handler and inline error message for join mutation.
- `share/[slug]/page.tsx`: Added `onError` handler and inline error message for import mutation.

### iOS (`apps/ios`)

- `AIChatView.swift`: Removed `.menuStyle(.borderlessButton)` — macOS-only API.
- `AIChatService.swift`: `moveConversation` captures value before spawning async `Task` to avoid stale index.
- `CalendarService.swift`: Replaced `hashValue` with stable packed-RGB extraction from CGColor components.
- `TaskCaptureService.swift`: Captures `folderId` before `context.delete`; marks unlinked tasks `.pendingUpload`.
- `EmailInboxView.swift`: Folder-change handler cancels debounce task before clearing `searchText` to prevent redundant `loadThreads` call.
- `ShareConversationSheet.swift`: Password validation guard added; `expiresInDays` now uses `apiValue` computed property.
- `GroupChatService.swift`: Replaced all `apiClient!` force-unwraps with a throwing `client()` helper; `createGroup` now matches returned group by id; added `GroupChatServiceError`.
- `ShareConversationService.swift`: Replaced `apiClient!` force-unwraps with `client()` helper; added `ShareConversationServiceError`.

### macOS (`apps/macos`)

- `MacAppServices.swift`: `syncSharedFolders` now guards on `authService.isAuthenticated`.
- `MacAssistantPanel.swift`: Removed `.swipeActions` (no-op in `ScrollView+LazyVStack`); moved Delete into ellipsis Menu.
- `CalendarService.swift`: Added `pruneFolderMap()` to remove stale event entries from UserDefaults.

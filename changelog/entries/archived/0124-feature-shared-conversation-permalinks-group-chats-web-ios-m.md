---
id: 0124
title: "Feature — Shared conversation permalinks + Group chats (web + iOS + macOS)"
status: archived
category: Added
release_date: 2026-03-31
source: CHANGELOG.md
---

## [2026-03-31] Feature — Shared conversation permalinks + Group chats (web + iOS + macOS)

### Backend — DB + tRPC

- **4 new Drizzle tables**: `shared_conversation`, `group`, `group_member`, `group_message` — all with proper FKs, cascade rules, and indexes. Migration `0041_lame_emma_frost.sql` generated and applied.
- **`sharing` tRPC router** (6 procedures): `create`, `get`, `import`, `listMine`, `revoke`, `update`. Password hashing via Web Crypto PBKDF2 (100k iterations, SHA-256). Rate-limited public `get` (20 req/min via Upstash Redis).
- **`groups` tRPC router** (11 procedures): `create`, `getByInvite`, `join`, `leave`, `listMine`, `sendMessage`, `listMessages`, `get`, `update`, `kickMember`, `regenerateInvite`, `delete`. AI responses generated in background via `waitUntil`. Message rate-limited (30/min per user).
- Both routers registered in `apps/server/src/trpc/index.ts`.

### Web

- New routes: `/share/:slug` (public shared conversation), `/g/:token` (group invite join), `/settings/sharing` (manage shared links).
- `ShareConversationModal` component — title, visibility (public/protected), password, expiry.
- `GroupChatView` — 5-second `refetchInterval` polling with `TODO(realtime)` comment.
- Share button wired into `ai-sidebar.tsx`; group sidebar section added to `app-sidebar.tsx`.

### iOS

- `ShareConversationService` + `GroupChatService` (polling, `TODO(realtime)` marker).
- `ShareConversationSheet` — create share link from AI chat menu; success state with native `ShareLink`.
- `SharedConversationView` — read-only with password gate; opened via `todus://share?slug=...` deep link.
- `GroupListView` + `GroupChatView` (iOS) — create/join/leave groups, member avatars, polling composer.
- `AIChatView` Share menu item redirects to `ShareConversationSheet` when conversation is saved.
- Deep link `todus://share?slug=...` handled in `TodosApp.swift`.
- `AppServices` extended with `shareConversationService` and `groupChatService`.

### macOS

- `MacShareConversationPanel` — popover from AI assistant ellipsis menu.
- `MacGroupChatView` — HSplitView with member list + message area, polling.
- `MacGroupListSection` — sidebar section with create/join actions.
- `MacSidebarView` updated with `selectedGroupId` binding and Groups section.
- `MacRootView` shows `MacGroupChatView` in detail pane when a group is selected.
- `MacAppServices` extended with `shareConversationService` and `groupChatService`.

**Files:** `apps/server/src/db/schema.ts`, `apps/server/src/trpc/routes/sharing.ts` (new), `apps/server/src/trpc/routes/groups.ts` (new), `apps/server/src/trpc/index.ts`, `apps/mail/app/routes.ts`, `apps/mail/app/(full-width)/share/[slug]/page.tsx` (new), `apps/mail/app/(full-width)/group-join/[token]/page.tsx` (new), `apps/mail/components/ui/share-conversation-modal.tsx` (new), `apps/mail/components/ui/group-chat-view.tsx` (new), `apps/mail/components/ui/ai-sidebar.tsx`, `apps/mail/app/(routes)/settings/sharing/page.tsx` (new), `apps/ios/…/ShareConversationService.swift` (new), `apps/ios/…/GroupChatService.swift` (new), `apps/ios/…/ShareConversationSheet.swift` (new), `apps/ios/…/SharedConversationView.swift` (new), `apps/ios/…/GroupChatView.swift` (new), `apps/ios/…/AIChatView.swift`, `apps/ios/…/AppServices.swift`, `apps/ios/…/TodosApp.swift`, `apps/macos/…/MacShareConversationPanel.swift` (new), `apps/macos/…/MacGroupChatView.swift` (new), `apps/macos/…/MacSidebarView.swift`, `apps/macos/…/MacRootView.swift`, `apps/macos/…/MacAppServices.swift`

# Project Changelog

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

---

## [2026-03-31] Fix — C2: Web home page — distinguish "not connected" from empty state

### Web — `home/page.tsx`
- **Calendar section**: Replaces static "Connect Google Calendar" CTA with real `trpc.calendar.events` query for today. Shows live events with colored left border, time, and optional location. `scopeMissing = true` → re-auth button. No events → "No events today".
- **Email section**: Checks `threadsQuery.isError` to surface "Connect Gmail" CTA (backend returns `NOT_FOUND` when no connection) vs "Your inbox is empty" when connected with no threads.
- Added `CalendarEventRow` component for compact event rendering (colored border, time label, location).

**Files:** `apps/web/app/(routes)/mail/home/page.tsx`

---

## [2026-03-31] Feature — S1: Google Calendar integration (backend + web)

### Backend — `calendar.ts` + `trpc/index.ts` + `driver/google.ts`
- New `calendarRouter` with `events` and `calendars` queries — calls Google Calendar API v3 using `OAuth2Client` (auto-refresh via stored `refreshToken`)
- `calendar.readonly` scope added to Google driver's `getScope()` — included in all new auth flows
- 403 "scope missing" handled gracefully: returns `{ events: [], scopeMissing: true }` so the frontend can prompt a re-auth rather than surfacing an error

### Web — `calendar/page.tsx`
- Calendar page now fetches real Google Calendar events for the displayed month
- Right panel shows events (colored left border, time, location) above tasks; unified empty state
- Week overview shows blue dots on days with events
- `scopeMissing = true` → "Connect Google Calendar" banner with `authClient.linkSocial` re-auth
- Page title reverted to "Calendar" now that real events are shown

**Files:** `apps/server/src/trpc/routes/calendar.ts` (new), `apps/server/src/trpc/index.ts`, `apps/server/src/lib/driver/google.ts`, `apps/web/app/(routes)/mail/calendar/page.tsx`

---

## [2026-03-31] Feature — S3: iOS Settings navigation-based restructure

### iOS — `SettingsView.swift`
- Active Sessions → `SessionsSettingsView` sub-page; main settings shows session-count badge NavigationLink
- AI Assistant → `AIAssistantSettingsView` sub-page (two large TextEditors removed from main list); profile saved on `.onDisappear`
- Appearance → `AppearanceSettingsView` sub-page (vertical row list replaces cramped three-column picker); main settings shows current theme name as subtitle
- Removed unused `headerCell`, `valueCell`, `formatSessionDate`, `revokingSessionIDs`, `isRevokingAllSessions` from main view

**Files:** `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`

---

## [2026-03-31] UX Polish — web mail first-run and inbox clarity pass

- Reworked the first-run flow in `apps/mail` so onboarding no longer competes with inbox connection setup. The inbox tour now waits until the user has at least one connected account.
- Replaced the blocking connect-email modal with a dismissible setup card, so users can orient themselves or navigate to settings without being trapped in a modal on first load.
- Clarified primary inbox controls: the main search affordance now reads as `Search or filter mail`, the category dropdown is labeled `Filter inbox`, active filter counts use consistent wording, and the inbox/People toggle now explains what the People view does.
- Improved thread-list discoverability by keeping row actions lightly visible instead of fully hidden until hover, and upgraded empty states with clearer, action-oriented copy.
- Simplified thread-header hierarchy by making `Reply all` the obvious primary action and moving notes into secondary actions, while also making the AI entry point more concrete through updated tooltip/call-to-action language.
- Tightened onboarding copy to focus on immediate email tasks instead of vague marketing or future-looking messaging.

**User-facing:** First-time users get a calmer setup flow, inbox controls are easier to understand within a few seconds, and the main email actions are more obvious.

**Files:** `apps/mail/components/onboarding.tsx`, `apps/mail/components/connection/connection-wrapper.tsx`, `apps/mail/components/mail/mail.tsx`, `apps/mail/components/mail/mail-list.tsx`, `apps/mail/components/mail/thread-display.tsx`, `apps/mail/components/mail/note-panel.tsx`, `apps/mail/components/ai-toggle-button.tsx`, `TASK.md`

## [2026-03-31] Fix — iOS: email inbox 4-state branching (loading / error / empty / results)

### iOS — `EmailInboxView.swift`

- Added `errorState` view: `exclamationmark.triangle` icon, "Couldn't load \(folder)" title, backend error message as subtitle, "Try Again" button
- Body condition now has 4 branches: no-connection → skeleton (isLoading && empty) → **error** (errorMessage != nil && empty && !loading) → empty → thread list
- `emptyState` now branches: search-empty ("No results for X", Clear Search button) vs folder-empty (folder icon, Refresh button)
- Fixed bug: `searchBar.onSubmit` was calling `loadThreads(query:refresh:)` without `folder:` — now passes `selectedFolder.rawValue`

**Files:** `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`

## [2026-03-31] UX Polish — email folder parity on iOS and macOS

### iOS — `EmailInboxView.swift`

- Added `EmailFolder` private enum covering all 7 backend folders: inbox, drafts, sent, archive, snoozed, spam, bin (trash)
- Header title is now tappable — opens a `Menu` folder picker with icons, divided into primary (Inbox/Drafts/Sent) and secondary (Archive/Snoozed/Spam/Trash) groups
- Folder changes clear the search field and reload threads via `loadThreads(folder:refresh:)`
- Loading skeleton, empty state icon, and empty state title all reflect the active folder

### macOS — `MacRootView.swift` + `MacSidebarView.swift`

- Extended `EmailSection` enum with four new cases: `.archive`, `.snoozed`, `.spam`, `.bin` — each with a `title`, `systemImage`, and `isPrimary` flag
- Sidebar email sub-items now show icons alongside text (updated `SidebarChildItemButton` to accept optional `systemImage`)
- Primary folders (Inbox, Drafts, Sent) appear above a subtle divider; secondary folders below
- `MacEmailInboxView(folder: section.rawValue)` already routes the raw value to the backend — no additional changes needed

**Files:** `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`, `apps/macos/TodusMac/App/MacRootView.swift`, `apps/macos/TodusMac/App/MacSidebarView.swift`, `apps/macos/TodusMac/Views/Email/MacEmailInboxView.swift`

## [2026-03-31] Feature — web: shareable thread summary copy action

- Added a one-click `Copy summary` action to the thread summary card in `apps/mail/components/mail/mail-display.tsx`.
- The copied payload includes the thread subject, the AI summary, and a short Todus attribution footer so it can be pasted into email or Slack as a branded handoff.
- Added PostHog tracking for successful shares via `Thread Summary Shared`.

**User-facing:** Users can now turn an AI summary into a reusable share artifact without leaving the thread view.

**Files:** `apps/mail/components/mail/mail-display.tsx`, `TASK.md`

## [2026-03-31] Fix — privacy settings sender removal submits form

- Added `type="button"` to the trusted-sender removal control in `apps/mail/app/(routes)/settings/privacy/page.tsx` so clicking the remove icon no longer triggers the surrounding form submit.

**Files:** `apps/mail/app/(routes)/settings/privacy/page.tsx`, `TASK.md`

## [2026-03-31] Fix — categories settings state sync

- Updated `apps/mail/app/(routes)/settings/categories/page.tsx` so the local categories state rehydrates from `initialCategories` when fresh server data arrives, instead of relying on a stale effect dependency. Also removed the loose `any` type from the field-change prop.

**Files:** `apps/mail/app/(routes)/settings/categories/page.tsx`, `TASK.md`

## [2026-03-31] Fix — web root error boundary hook order

- Split the root error boundary in `apps/mail/app/root.tsx` so the 404 branch returns before any hooks and the Sentry/reporting side effects live in a dedicated child component. This removes the conditional hook call that violated `react-hooks/rules-of-hooks`.

**Files:** `apps/mail/app/root.tsx`, `TASK.md`

## [2026-03-31] UX Polish — cross-platform UX fixes (iOS, macOS, Web)

Comprehensive UX pass addressing discoverability, friction, and honesty gaps across all three live platforms.

### macOS

- **Removed non-functional Quick Filters** from tasks sidebar footer — buttons had nil closures and did nothing (`MacSidebarView.swift`)
- **Removed hardcoded email labels & calendar sources** from sidebar footer — "Important/Work/Personal" labels and calendar source pills were static UI not backed by real data (`MacSidebarView.swift`)
- **Removed non-functional toolbar filter menus** — email (All Mail/Unread/Flagged) and tasks (All/Today/Upcoming/Completed) filters had empty closures; "Mark All Read" is the only remaining email toolbar action (`MacRootView.swift`)
- **Removed dead notification bell** — popover showed hardcoded "No new notifications." placeholder (`MacRootView.swift`)
- **Confirmed Email and AI Assistant are already separate sections** in `MacSettingsView.swift` — no change needed

### iOS

- **Split Settings: "Email & AI" → separate "Email" + "AI Assistant" sections** — reduces cognitive load; unrelated settings no longer grouped (`SettingsView.swift`)
- **Replaced horizontal-scroll sessions table with vertical cards** — mobile-friendly layout with "This device" badge and per-session log out (`SettingsView.swift`)
- **Added skeleton loading state to email inbox** — differentiates loading vs empty vs error; `.redacted(reason: .placeholder)` blocks shown during initial fetch (`EmailInboxView.swift`)

### Web

- **Honest Calendar page labeling** — title changed from "Calendar" to "Tasks by Date" with "Calendar events coming soon" badge; misleading "Connect Google Calendar" link removed (`calendar/page.tsx`)
- **Quick Actions on Search page** — initial empty state now shows inline task-create field (type + Enter) and "Compose new email" button, matching macOS quick-action pattern (`search/page.tsx`)

**Files:** `apps/macos/TodusMac/App/MacSidebarView.swift`, `apps/macos/TodusMac/App/MacRootView.swift`, `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`, `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`, `apps/web/app/(routes)/mail/calendar/page.tsx`, `apps/web/app/(routes)/mail/search/page.tsx`

## [2026-03-31] Refactor — `resolveCurrentSessionId` Bearer guard clarity

- Replaced `!authHeader?.startsWith('Bearer ')` with `!authHeader || !authHeader.startsWith('Bearer ')` in `apps/server/src/trpc/routes/sessions.ts`. Behavior is unchanged (null/empty headers still take the hint/early-return path only), but the guard matches the real invariant before `authHeader.slice()` and narrows types explicitly.

**Files:** `apps/server/src/trpc/routes/sessions.ts`

## [2026-03-31] Fix — 3 targeted bugs: security nav, AI priority enum, prompt ordering

- **Security nav missing**: Added `navigation.settings.security` entry to `apps/web/config/navigation.ts` so the Active Sessions page (`/settings/security`) is reachable from the settings sidebar. Route and i18n key already existed; the nav link was the only missing piece.
- **Stale 'urgent' priority in AI tool definitions**: Removed `'urgent'` from the priority enum in both `create_task` and `update_task` tool definitions in `apps/server/src/routes/ai.ts`. The server tRPC schema (`tasks.ts`) only accepts `['none','low','medium','high']`; any AI-generated `priority: 'urgent'` would fail validation.
- **AI profile prepended before system prompt**: Flipped ordering in `apps/server/src/routes/agent/index.ts` (ZeroAgent) and `apps/server/src/routes/ai.ts` (`/ai/chat` and `/ai/call`) so the base system instructions appear first and user profile context is appended after, ensuring core rules are not shadowed by user content.

**User-facing:** Security page now appears in settings sidebar. AI task creation with priority no longer silently fails. AI assistant behavior is more stable when users set custom profiles.

**Files:** `apps/web/config/navigation.ts`, `apps/server/src/routes/ai.ts`, `apps/server/src/routes/agent/index.ts`

## [2026-03-31] Fix — server auth: prevent repeated onboarding email campaigns

- Persist the `welcomeEmailSent` guard before dispatching onboarding campaigns so a partial Resend failure can no longer replay the entire sequence on the next login.
- Made onboarding campaign dispatch best-effort per email so one failed scheduled message does not block the rest of the sequence or reopen the send gate.

**User-facing:** New and returning users should stop receiving repeated "Welcome", "Todus Pro is here", and related onboarding emails on every login.

**Files:** `apps/server/src/lib/auth.ts`, `TASK.md`

## [2026-03-31] Feature — web: Full iOS/macOS visual parity pass (Tasks board/table, Home redesign, Chat history, Calendar quick-add)

### Tasks page (`/mail/tasks`) — full rewrite

- **View mode picker**: segmented control (List / Board / Table) at top right
- **Horizontal folder pill strip**: scrollable row of pills replaces old sidebar layout — "All" + each folder + "+" add folder button
- **Board view** (kanban): 3 draggable columns (To Do / Doing / Done) using `@dnd-kit/core`. Drag cards between columns to update `status` via `tasks.update`. `DragOverlay` renders the card while dragging.
- **Table view**: compact single-line `<table>` rows (checkbox, title, priority, status, due, folder, menu) — dense Linear-style view
- **Quick-add row**: inline text input at top of list view — Enter creates task with current folder pre-selected
- **Task detail Sheet**: clicking a task title opens a `<Sheet side="right">` with full metadata (title, description, priority, status, due date, folder), edit + delete buttons
- **TypeScript fix**: `isDueDateWarning` now accepts `string | Date | null | undefined` since tRPC can return `Date` objects

### Home page (`/mail/home`) — redesign

- **Section headers**: iOS-style `SectionHeader` component — icon + title + count badge + "See all" link + optional "+" button
- **Today's Events section**: "Connect Google Calendar" CTA card (dashed border, links to Settings → Connections). No fake data shown since backend Calendar API isn't wired yet.
- **Sections**: Events → Due Tasks → Recent Emails (matches iOS order)
- **Card containers**: each section wrapped in `rounded-xl border bg-card px-4 py-4`
- **Greeting**: larger `text-[22px]` heading with date subtitle

### Chat page (`/mail/chat`) — conversation history + markdown

- **Left sidebar** (hidden on mobile): `w-56` conversation list from `ai.listConversations`. Each row shows title + relative date. Active row highlighted with `bg-accent`.
- **Load conversation**: clicking a past chat loads its messages via `ai.getConversation` and restores to `setMessages()`
- **Auto-save**: on first assistant response (not mid-stream), saves conversation with title = first 60 chars of user's first message via `ai.saveConversation`
- **Delete**: hover → MoreHorizontal → dropdown → Delete triggers `ai.deleteConversation`, refreshes sidebar
- **Markdown**: AI responses rendered with `react-markdown` + `remark-gfm` inside `prose prose-sm dark:prose-invert` container (wrapped in div — react-markdown v10 doesn't accept className directly)
- **AI bubble style**: `border bg-card` instead of plain `bg-muted` for visual separation

### Calendar page (`/mail/calendar`) — polish + features

- **Inline quick-add row**: always-visible input at top of day panel — Enter creates task with `dueDate = selectedDate`
- **Connect Google Calendar CTA**: dashed-border card in left sidebar below week overview, links to Settings → Connections
- **Week overview**: dates with tasks show count badge
- **Empty state**: shows link to Tasks page
- **Header**: slimmer `py-3.5` consistent with other page headers

**Files:**

- `apps/web/app/(routes)/mail/tasks/page.tsx` — full rewrite
- `apps/web/app/(routes)/mail/home/page.tsx` — full rewrite
- `apps/web/app/(routes)/mail/chat/page.tsx` — full rewrite
- `apps/web/app/(routes)/mail/calendar/page.tsx` — full rewrite
- `apps/web/config/navigation.ts` — Email expandable parent + icon updates
- `apps/web/components/ui/nav-main.tsx` — NavItemExpandable, NavChildRow, removed feedback link
- `apps/web/components/ui/app-sidebar.tsx` — removed dead badge mutations
- `apps/web/components/ai-toggle-button.tsx` — circular FAB polish

## [2026-03-30] Feature — web: iOS/macOS feature parity (Folders, AI Chat, Global Search)

- **Task Folders**: Tasks page now has a folder sidebar (create/rename/delete folders, filter tasks by folder, move tasks to folders via dropdown). Backend `folders.list/create/update/delete` tRPC routes fully wired.
- **AI Chat page** (`/mail/chat`): Standalone full-page chat using `useAgent` + `useAgentChat` from Cloudflare `agents` SDK. Connects to `ZeroAgent` Durable Object via WebSocket. Example queries, streaming indicator, stop button.
- **Global Search page** (`/mail/search`): Searches both emails (via `mail.listThreads` with `q` param) and tasks (via `tasks.list` with `search` param) simultaneously. Tabbed result view (All / Emails / Tasks), debounced input, empty/loading states.
- **Navigation**: Added AI Chat and Search items to sidebar "Organize" section with keyboard shortcuts. Added `navigation.sidebar.chat` and `navigation.sidebar.search` i18n keys.
- **Routes**: Registered `/mail/chat` and `/mail/search` in `routes.ts`.

**Files:** `apps/web/app/(routes)/mail/tasks/page.tsx`, `apps/web/app/(routes)/mail/chat/page.tsx` (new), `apps/web/app/(routes)/mail/search/page.tsx` (new), `apps/web/app/routes.ts`, `apps/web/config/navigation.ts`, `apps/web/messages/en.json`

## [2026-03-31] Fix — web: invalidate all `tasks.list` queries after task mutations

- Task updates from mail home, calendar, and shared `TaskItem` now call `queryClient.invalidateQueries(trpc.tasks.list.queryFilter())` so every cached `tasks.list` variant (filters, sort, limit) refetches instead of only the one matching a fixed `queryKey({ limit: N })`.
- Mail tasks page `invalidate()` uses the same `queryFilter()` pattern (replacing a path-prefix `predicate` that relied on reference equality between fresh and cached `queryKey[0]` arrays).

**User-facing:** Lists and filters stay in sync after toggling or editing tasks from any surface.

**Files:** `apps/web/app/(routes)/mail/tasks/page.tsx`, `apps/web/app/(routes)/mail/home/page.tsx`, `apps/web/app/(routes)/mail/calendar/page.tsx`, `apps/web/components/tasks/task-item.tsx`, `apps/web/task-item.tsx`

## [2026-03-31] Fix — iOS AI chat: transcribe freeze, full-screen hang, expand button visibility

- Fixed transcribe button freezing the UI by moving `AVAudioSession.setActive` off the main actor with `Task.detached` in `VoiceController.beginAudioSession()`.
- Fixed full-screen compose button causing a 5-second hang by delaying `isFocused = true` until after the sheet presentation animation completes (~350ms).
- Full-screen expand button is now only shown when the text input has reached its maximum height (≥118pt), hiding it when the input is empty or single-line.

**Files:** `apps/ios/Todus/Todus/Features/Voice/VoiceInputButton.swift`, `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`

## [2026-03-31] Fix — shared keychain auth remains backward compatible

- Restored backward-compatible reads for legacy account-only Keychain items after adding the bundle service namespace.
- New writes still use the namespaced keychain entry, but upgrade installs now fall back to the previous storage shape so persisted bearer tokens and AI chat history survive the rollout.

**Files:** `packages/swift-auth/Sources/TodusAuth/KeychainHelper.swift`

## [2026-03-30] Feature — active sessions management in `apps/web`, iOS, and macOS

- Added a new backend `sessions` tRPC router with `list`, `revoke`, and `revokeAll`, backed by a new `mail0_session_metadata` table for coarse device/location metadata and last-seen tracking.
- Replaced the `apps/web` security placeholder with a real Active Sessions table showing `Device`, `Location`, `Created`, `Updated`, and per-session `Log out`, plus a `Log out all devices` action.
- Added matching Active Sessions management UI to iOS and macOS settings so signed-in devices can be reviewed and revoked from native clients too.
- Improved native current-session detection by resolving raw Better Auth session tokens from the session table when cookie session lookup is unavailable, and by forwarding the Better Auth `session.id` through the native OAuth handoff for JWT-based native sessions.
- Intentionally left cross-device live sync work out of this change set; that architecture remains a separate follow-up because it touches tasks, settings, AI state, and native persistence broadly.

**Files:** `apps/server/src/db/schema.ts`, `apps/server/src/db/migrations/0040_stiff_living_lightning.sql`, `apps/server/src/main.ts`, `apps/server/src/trpc/index.ts`, `apps/server/src/trpc/routes/sessions.ts`, `apps/web/app/(routes)/settings/security/page.tsx`, `apps/ios/Todus/Todus/Services/API/TodosAPIClient.swift`, `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`, `apps/macos/TodusMac/Services/API/TodosAPIClient.swift`, `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`, `packages/swift-auth/Sources/TodusAuth/AuthService.swift`, `TASK.md`

## [2026-03-30] Fix — archived RN parity and safety cleanup

- Hardened the archived RN auth, settings, and mail flows against stale optimistic state, unhandled URL opening errors, and unsafe persistence failures.
- Removed raw email from native PostHog identification, added safer Postgres healthcheck behavior in production compose, and closed Hyperdrive connections in the server auth token path.
- Updated shared compose/mail helpers and several settings screens to handle loading, error, and accessibility cases more defensively.

**Files:** `apps/server/src/main.ts`, `docker-compose.prod.yaml`, `apps/archived/archived-rn/...`

## [2026-03-30] Fix — native Google OAuth now returns a JWT bearer token for iOS/macOS

- Updated `/api/auth/mobile-token` to mint a JWT via Better Auth's `jwt()` plugin (`auth.api.getToken`) instead of forwarding the raw session token from the browser session.
- Kept the server auth middleware fallback paths in place, but the native callback now receives the JWT format that `/api/auth/me` already verifies directly.
- Updated the shared native auth comments so the callback token format is documented correctly again.

**Files:** `apps/server/src/main.ts`, `packages/swift-auth/Sources/TodusAuth/AuthService.swift`

## [2026-03-30] Fix — macOS centralized sign-out now clears email state before auth reset

- Updated the macOS `MacAppServices.signOut()` path to call `emailService.resetForSignOut()` before `authService.signOut()`.
- Removed the stale TODO from the centralized sign-out method so logout behavior now matches the sidebar and settings call sites that already route through this method.
- This prevents cached email threads, pagination tokens, connection status, and email errors from surviving logout and leaking into the next user session.

**Files:** `apps/macos/TodusMac/App/MacAppServices.swift`

## [2026-03-30] Fix — native auth session-expired state now survives sign-out, and Keychain save failures are observable

- Reordered the shared native auth invalid-session flow so `signOut()` runs before the session-expired flag and user-facing error are set, which preserves the warning banner/message instead of clearing them immediately.
- Applied the same ordering in persisted-session restoration so invalid saved sessions now leave the app in a consistent expired state after sign-out.
- Upgraded shared Keychain writes to return success/failure and log OSStatus details instead of silently ignoring `SecItemAdd` / `SecItemDelete` failures.
- Updated iOS and macOS AI conversation persistence to check the new Keychain write result and log failures instead of dropping them silently.
- Verified the macOS project `LastUpgradeCheck = 2640` already matches the installed Xcode 26.4 toolchain, so no project file change was required.

**Files:** `packages/swift-auth/Sources/TodusAuth/AuthService.swift`, `packages/swift-auth/Sources/TodusAuth/KeychainHelper.swift`, `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`, `apps/macos/TodusMac/Services/AI/MacAIChatService.swift`

## [2026-03-30] Fix — Cloudflare install now respects the web workspace lockfile

- Regenerated `pnpm-lock.yaml` so the `apps/web` `uuid` / `@types/uuid` dependency entries match `apps/web/package.json` again.
- Kept the dependency update scoped to the lockfile only; no app source changes were required for this deploy fix.

**Files:** `pnpm-lock.yaml`

## [2026-03-30] Fix — macOS search modal now searches calendar events and opens real actions

- Wired the macOS search modal to actual app callbacks so quick actions now open task creation, email compose, and new event flows instead of rendering inert rows.
- Added calendar event loading and search indexing to the modal so event names from the home dashboard now appear in search results.
- Improved the empty state with actionable suggestions and tap targets for common follow-up actions.
- Added direct navigation for search results so task, email, and event rows move the user into the right surface instead of doing nothing.

**Files:** `apps/macos/TodusMac/Views/Search/MacSearchView.swift`, `apps/macos/TodusMac/App/MacRootView.swift`

## [2026-03-30] Fix — macOS native auth now verifies session before entering the app shell

- Hardened the shared native `AuthService` so Google/Apple/OTP callbacks no longer mark the app as authenticated from token presence alone.
- Added post-callback `/api/auth/me` verification with short retry backoff to absorb the native OAuth handoff window before profile hydration completes.
- Added callback deduping so macOS dual callback entrypoints cannot race the same token through auth completion twice.
- Added explicit persisted-session restoration on macOS launch so stale Keychain state is rejected before the main shell renders.
- Namespaced native Keychain entries by bundle-specific service to make session storage deterministic across iOS/macOS and to make full local resets reliable.
- Added a DEBUG-only auth section in macOS Settings showing auth state, token preview, session-expired flag, and profile email for faster diagnosis.

**Files:** `packages/swift-auth/Sources/TodusAuth/AuthService.swift`, `packages/swift-auth/Sources/TodusAuth/KeychainHelper.swift`, `apps/macos/TodusMac/App/MacRootView.swift`, `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`, `apps/macos/README.md`, `TASK.md`

## [2026-03-30] Fix — macOS sidebar profile menu now opens settings

- Removed the no-op `Profile` item from the macOS sidebar account dropdown.
- Wired the profile menu entry to the existing macOS settings overlay so it now opens real profile/account controls.
- Kept the separate gear icon and keyboard shortcut as alternate settings entry points.

**Files:** `apps/macos/TodusMac/App/MacSidebarView.swift`, `apps/macos/README.md`

## [2026-03-30] Polish — macOS Calendar UI Round 5

- **Tap-to-create on time grid:** Tapping empty space in Day/Week time grid opens Apple Calendar's new event dialog at that time (snapped to 30-min slot). Uses `x-apple-calevent://new` URL scheme.
- **Segmented control visibility:** Replaced invisible `.thinMaterial` highlight with solid opaque pill (`Color(white: 0.22)` dark, white light) + shadow. Outer track uses matching solid color (`Color(white: 0.13)` dark) instead of `.ultraThickMaterial`.
- **Unified header controls:** Nav arrows, Today button, and segmented picker all use the same `controlBg` color and `headerControlHeight` (30pt). No more mismatched materials/heights.
- **Month view: prev/next month days visible muted:** Empty cells at month start/end now show actual dates from the previous/next months at 35% opacity — matching Apple Calendar behavior.
- **Month view: instant transitions:** Removed animation on month navigation. `.animation(.none, value: selectedDate)` on the grid prevents the "circus" effect of cells moving around.
- **Month view: scrollable:** Grid remains wrapped in ScrollView for overflow.

**Files:** `MacCalendarView.swift`, `CalendarTimeGridView.swift`

## [2026-03-30] Fix — macOS `EmailService.resetForSignOut()` (compile unblock)

- Implemented the missing `resetForSignOut()` on macOS `EmailService` so callers that clear cached threads, pagination, errors, and connection flags after sign-out resolve at link time.
- **Impact:** Fixes a hard build failure (undefined symbol) once logout/delete-account paths reference this API; unrelated to calendar UI work beyond sharing the same release.

**Files:** `apps/macos/TodusMac/Services/Email/EmailService.swift`

## [2026-03-30] Fix — macOS logout now resets email state before auth sign-out

- Centralized macOS sign-out in `MacAppServices.signOut()` so logout now mirrors the iOS flow.
- Added the missing `emailService.resetForSignOut()` call before `authService.signOut()` to clear threads, connection status, and error state on logout.
- Updated both macOS logout entry points to call the shared service helper:
  - Settings confirmation dialog
  - Sidebar user menu
- Also switched the macOS delete-account flow to the same helper so it leaves the app in a clean post-sign-out state.

**Files:**

- `apps/macos/TodusMac/App/MacAppServices.swift`
- `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`
- `apps/macos/TodusMac/App/MacSidebarView.swift`

## [2026-03-30] Fix — macOS/iOS native apps: user profile not loading after OAuth login

**Root cause (3 layers):**

1. Better Auth's HTTP `/auth/get-session` returns `null` for bearer-token requests (200 status, body: `null`)
2. The Hono middleware's JWT fallback tried to verify the 32-char session token as a JWT → threw silently
3. Variable shadowing: `const session = await auth.api.getSession()` shadowed the Drizzle `session` schema table, so the session token DB lookup used the wrong object

**Fix:**

- Renamed middleware variable to `authSession` to avoid shadowing the Drizzle `session` schema import
- Added session token DB lookup fallback: when JWT verification fails, looks up the raw token in the `session` table and resolves the user
- Added `GET /api/auth/me` endpoint that returns `c.var.sessionUser` from middleware context
- Updated shared `fetchUserProfile()` to use `/api/auth/me` instead of `/api/auth/get-session`
- Added `.task(id: isAuthenticated)` to MacRootView so profile fetch re-runs after login
- Added `.task { fetchUserProfile() }` to MacSettingsView

**Files:**

- `apps/server/src/main.ts` — `authSession` rename, session token lookup fallback, `/api/auth/me` endpoint
- `packages/swift-auth/Sources/TodusAuth/AuthService.swift` — Use `/auth/me`, debug logging
- `apps/macos/TodusMac/App/MacRootView.swift` — `.task(id: isAuthenticated)` for profile fetch
- `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift` — `.task { fetchUserProfile() }` on open

**Requires:** Backend redeployment (`pnpm deploy:backend`)

## [2026-03-30] Fix — iOS create-sheet attachment fallback and board regrouping

- Forwarded the captured attachment list into event creation fallback paths so failed calendar permission or event-creation errors still preserve user-selected attachments when creating a task instead.
- Restored the Kanban regroup observer using a task signature derived from each task's id, status, and folder so in-place SwiftData mutations move cards between columns again.

**Files:** `apps/ios/Todus/Todus/Navigation/CreateSheet.swift`, `apps/ios/Todus/Todus/Features/Tasks/BoardView.swift`

## [2026-03-30] Fix — iOS hang triage instrumentation and shell pressure reduction

- Deferred non-critical root startup work so launch no longer immediately competes with reminders import/sync and legacy auth-upgrade work.
- Switched the iOS shell back to rendering only the active tab, reducing hidden SwiftUI invalidation and background work during tab switches, focus changes, and general interaction.
- Added Instruments-friendly trace points around app initialization, deferred startup, tab switching, SwiftData saves, email thread loading, and reminders sync/import.
- Cached bearer tokens in-memory inside the shared native auth service and moved profile/token metadata persistence off the synchronous main-actor path to reduce Security/Keychain stalls.
- Prevented the email inbox from re-running its full initial fetch every time the tab becomes visible, and fixed a create-sheet fallback path so event creation failures preserve attachments when falling back to task capture.

**Files:** `TodosApp.swift`, `RootView.swift`, `MainTabView.swift`, `AppServices.swift`, `AppLogger.swift`, `EmailService.swift`, `EmailInboxView.swift`, `TaskCaptureService.swift`, `BoardView.swift`, `CreateSheet.swift`, `AuthService.swift`

## [2026-03-30] Fix — native sync, calendar, and accessibility cleanup

- Kept the marketing home avatar text consistent with the existing `adam.jpg` asset in both web shells.
- Restored a 44pt task-row checkbox hit area, removed the root macOS focus-ring suppression, and added a visible focus style to the Gmail connect button.
- Made macOS calendar month/all-day event pills tappable, tightened the time-grid math, and disabled the misleading empty delete actions.
- Added conversation-delete persistence so local removals survive sync, plus retry handling for pending backend deletes on iOS/macOS.
- Hardened the backend conversation upsert against cross-user overwrite, and aligned the latest migration with task checks, timestamp triggers, OAuth foreign keys, and the writing-style matrix column rename.

**Files:** `HomeContent.tsx` (web + mail), `TaskRowView.swift`, `CreateSheet.swift`, `TodosAPIClient.swift` (iOS + macOS), `MacRootView.swift`, `MacTheme.swift`, `MacEmailInboxView.swift`, `CalendarEventBlockView.swift`, `CalendarTimeGridView.swift`, `MacCalendarView.swift`, `AIChatService.swift` (iOS + macOS), `schema.ts`, `0039_brainy_junta.sql`, `0039_snapshot.json`, `conversations.ts`

## [2026-03-30] Copy — Founder / demo names: Adam → Ludvig

- Marketing home mock UI, About founders copy, HR demo row, and AI brain fallback sample thread now use **Ludvig** (abbreviated **Ludvig H** in HR mock data) instead of Adam / Adam G.
- **Unchanged:** `Scarlett Adams` in mail demo data (surname, not the first name Adam).

**Files:** `HomeContent.tsx` (mail + web), `about.tsx` (mail + web), `hr.tsx` (mail + web), `brain.fallback.prompts.ts`

## [2026-03-30] Feature — Year view + Apple Calendar glass segmented control

- **Year view:** New infinitely-scrollable vertical year view showing 21 years (±10) as 4×3 grids of mini-month calendars. Each mini-month shows day numbers, today circled in red, event dot indicators (accent color), weekday initials. Tap a mini-month → navigate to Month view for that month. Auto-scrolls to current year on appear.
- **Glass segmented control:** Replaced native `Picker(.segmented)` with custom `CalendarViewModePicker` using Apple Calendar-style glass/material design — `.ultraThickMaterial` outer pill, `.thinMaterial` selected highlight, `matchedGeometryEffect` for smooth animated sliding, 4 segments (Day/Week/Month/Year). Respects light/dark mode via SwiftUI Material.
- **Header buttons:** Nav arrows and "Today" button now use `.ultraThinMaterial` glass backgrounds instead of solid `surfaceCard` — matches the new glass aesthetic across all header controls.
- **Control sizing:** Unified `headerControlHeight` to 28pt for better tap targets.

**Files:** `MacCalendarView.swift`

## [2026-03-30] Fix — macOS Calendar UI Round 4

- **Week view header too tall (ROOT CAUSE):** `Color.clear.frame(width:)` gutter spacer expanded vertically — replaced with `Text("")` + `.fixedSize(horizontal: false, vertical: true)` wrapper
- **Header buttons:** Nav arrows now fully circular (24pt `Circle()`), "Today" pill same 24pt height, all controls aligned
- **Month view scrolling:** Wrapped LazyVGrid in `ScrollView(.vertical)` inside GeometryReader
- **Event deduplication:** Holidays from multiple calendars deduplicated by title+date
- **Day view tint:** Removed blueish accent highlight, now neutral
- **Segmented picker:** Fixed text wrapping with `.labelsHidden()` + wider frame

**Files:** `MacCalendarView.swift`, `CalendarService.swift`, `CalendarTimeGridView.swift`

## [2026-03-30] Redesign — Unified Create Sheet (merged CaptureComposer into CreateSheet)

**Problem:** Two competing input systems (CaptureComposer in tasks tab + CreateSheet global overlay) overlapped visually. CaptureComposer sat under the tab bar and was unusable. CreateSheet lacked attachments, voice, and slash commands.

**Solution:** Removed CaptureComposer from tasks tab entirely. Merged all its features into CreateSheet:

- Attachments (photo picker, camera, file picker) with inline thumbnails
- Voice transcription (VoiceInputButton)
- Slash commands (/due-today, /due-tomorrow, /due-next-week, /in-one-hour)
- Image paste handling (PasteHandlingTextInput)
- Keyboard-aware positioning

**Visual improvements:**

- Scrim opacity 0.10 → 0.45 (clearly distinguishable modal overlay)
- Text input 28pt → 16pt (compact, not oversized)
- Default type always "Auto" (AI decides) regardless of which tab
- Tight, clean toolbar with folder/date/voice/send in a single row

**Files:**

- `CreateSheet.swift` — Major rewrite with all merged features
- `TasksTabView.swift` — Removed CaptureComposer and keyboard observer
- `MainTabView.swift` — Removed defaultType parameter and method
- `CaptureComposer.swift` — Removed CaptureComposer struct; kept shared types (RichComposerInput, PasteHandlingTextInput, CameraPicker)

## [2026-03-30] Fix — macOS/iOS user profile not loading after login (shows "User" / "?")

**Root cause:** Better Auth's HTTP `/auth/get-session` endpoint returns `null` for bearer-token-authenticated requests. The Hono middleware's `auth.api.getSession()` call resolves bearer tokens correctly (tRPC routes work), but the HTTP handler doesn't — so `fetchUserProfile()` always got `null` back.

**Fix:**

- Added `/api/auth/me` endpoint on backend that returns `c.var.sessionUser` from the middleware context (which properly resolves bearer tokens)
- Updated `fetchUserProfile()` in shared AuthService to use `/api/auth/me` instead of `/api/auth/get-session`
- Added `.task(id: isAuthenticated)` to MacRootView so profile fetch re-runs after login (not just on initial view appear)
- Added `.task { fetchUserProfile() }` to MacSettingsView to refresh on settings open

**Files:**

- `apps/server/src/main.ts` — New `/api/auth/me` endpoint
- `packages/swift-auth/Sources/TodusAuth/AuthService.swift` — Use `/auth/me`, added debug logging
- `apps/macos/TodusMac/App/MacRootView.swift` — `.task(id: isAuthenticated)` for profile fetch
- `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift` — `.task { fetchUserProfile() }` on open

**Requires:** Backend deployment before the native apps can fetch profile data.

## [2026-03-30] Fix — macOS Calendar UI Round 3 bugs

- **Week view all-day events:** Changed from vertical column layout to horizontal per-day-column layout matching Apple Calendar — each day column now shows its own all-day events, preventing the massive tall header
- **Event deduplication:** Holidays and events appearing from multiple calendar sources (e.g. iCloud + Google) are now deduplicated by title+date, keeping only the first occurrence
- **Day view background tint:** Removed blueish accent tint from today's column highlight — now uses neutral `Color.primary.opacity(0.015)` instead of `MacTheme.accent.opacity(0.025)`
- **Segmented picker wrapping:** Fixed "Vie\nw" text wrapping by removing the "View" label text, adding `.labelsHidden()`, and widening frame from 170→180pt

**Files:** `MacCalendarView.swift`, `CalendarService.swift`, `CalendarTimeGridView.swift`

## [2026-03-30] Fix — iOS calendar icon stretched + tasks page too bulky

- **Calendar icon:** Added explicit height to `AppleCalendarIconView` so GeometryReader doesn't stretch vertically
- **Search bar:** Reduced vertical padding (9→6) and changed to Capsule shape for a slimmer, rounded look
- **Task rows:** Reduced vertical padding (8→5) and checkbox height (44→32) for more compact list items
- **Completed task rows:** Reduced vertical padding (12→8) and corner radius (16→14)
- **Header spacing:** Reduced view mode picker vertical padding (12→4)

**Files:** `BrandIcons.swift`, `TasksTabView.swift`, `TaskRowView.swift`, `InboxView.swift`

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

## [2026-03-30] Fix — Bearer token rotation capture (root cause of "Session expired")

Better Auth's bearer plugin returns a rotated session token via `set-auth-token` header when `updateAge` extends the session. Neither iOS nor macOS captured this — they kept the old token until it expired, causing 401s.

- **`AuthService.swift`**: Added `captureRotatedToken(from:)` — checks responses for `set-auth-token` and stores new token. Called from `attemptSilentRefresh()` and `fetchUserProfile()`.
- **`TodosAPIClient.swift` (iOS + macOS)**: Calls `captureRotatedToken` on every API response.
- **`AIChatService.swift` / `MacAIChatService.swift`**: Capture on SSE stream responses.
- **`KeychainHelper.swift`**: Added `saveData`/`readData` for Data blobs.

## [2026-03-30] Fix — macOS AI chat 401 handling (silent refresh parity with iOS)

`MacAIChatService` now mirrors iOS: on HTTP 401 from `/api/ai/chat`, call `attemptSilentRefresh()` before treating the session as dead. Success → user message to retry; failure → `isSessionExpired = true` and re-auth prompt.

**Files:** `apps/macos/TodusMac/Services/AI/MacAIChatService.swift`

## [2026-03-30] Fix — macOS settings and assistant panel compile cleanup

Resolved the current macOS Xcode warnings/errors blocking the `TodusMac` build:

- restored the branded service-row helper used by `MacSettingsView`
- added the missing Apple Reminders connection flag used by the settings UI
- replaced the explicit `Selector(("showHelp:"))` call with `#selector`
- removed ineffective `nonisolated(unsafe)` storage annotations from `MacVoiceController` and updated the speech callback to hop back to the main actor

**Files changed:**

- `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift`
- `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift`

## [2026-03-30] Fix — `@zero/web` index route & routing parity with `apps/mail`

**Symptom:** Visiting `http://localhost:3000/` showed a non-interactive calendar stub with no sidebar or mail chrome.

**Root cause:** `react-router.config.ts` uses `appDirectory: 'app'`, so `index('page.tsx')` resolves to **`app/page.tsx`**, which had been a placeholder calendar — not the marketing `HomeContent` shell from `apps/mail`. The experimental `app-layout.tsx` wrapper also did not apply to `/`, so the index never matched the unified shell.

**Fix:** Replaced `app/page.tsx` with the same pattern as `apps/mail` (`HomeContent` + `clientLoader` redirect to `/mail/inbox` when authenticated). Replaced **`app/routes.ts`** with the same tree as **`apps/mail/app/routes.ts`** (removed outer `app-layout` and `/home`/`/tasks`/`/calendar` routes under that layout). Removed duplicate/orphan files: root `apps/web/page.tsx`, `app/app-layout.tsx`, `(routes)/home|tasks|calendar/page.tsx`.

**User-facing:** Logged-in users land in the real mail app (`AppSidebar`, folders, working mail UI). Guests still get the marketing home.

## [2026-03-30] Fix — iOS AI chat session expired error & cross-reinstall persistence

### Session expired despite being logged in

- **Root cause:** `AIChatService` returned "Session expired" immediately on HTTP 401 without attempting a silent session refresh. `TodosAPIClient` already handled this correctly.
- **Fix:** On 401, attempt `authService.attemptSilentRefresh()` first. If refresh succeeds, prompt user to retry. If it fails, mark `isSessionExpired = true` for proper re-auth flow.
- **File:** `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`

### Chat history lost on reinstall

- **Root cause:** Conversations stored in `UserDefaults` which is wiped when the app is uninstalled.
- **Fix:** Moved conversation persistence to Keychain (`KeychainHelper.saveData`/`readData`), which survives app reinstalls. Includes automatic migration from old `UserDefaults` storage.
- **Files:** `packages/swift-auth/Sources/TodusAuth/KeychainHelper.swift` (added Data methods), `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`

## [2026-03-30] Fix — macOS app shows "User" with "?" avatar after Google OAuth login

**Root cause:** macOS app never called `fetchUserProfile()` on launch or when settings opened. The iOS app calls it in both `RootView.task{}` and `SettingsView.task{}`, but the macOS equivalents were missing these calls. The only profile fetch happened in `completeAuthentication()`'s fire-and-forget `Task{}`, which could silently fail during the auth→main view transition.

**Fix:** Added `fetchUserProfile()` calls to match iOS behavior:

- `MacRootView.swift` — new `.task{}` that fetches profile on app start
- `MacSettingsView.swift` — new `.task{}` that refreshes profile when settings opens

**Files changed:**

- `apps/macos/TodusMac/App/MacRootView.swift` — Added `.task { await services.authService.fetchUserProfile() }`
- `apps/macos/TodusMac/Views/Settings/MacSettingsView.swift` — Added `.task { await services.authService.fetchUserProfile() }`

## [2026-03-30] Polish — iOS AI assistant input bar refinements

Five targeted UX improvements to the iOS AI chat input area:

- **Tighter button sizing**: Standardized all action buttons (waveform, mic, send) to consistent 34×34 outer frames with 6pt spacing (was mixed 36/30 with 4/8pt spacing)
- **Tap-outside to blur**: Tapping anywhere in the chat area now resigns keyboard focus (previously only dismissed attachment picker)
- **Top-right toolbar breathing room**: Reduced HStack spacing to 16pt and added 2pt trailing padding on ellipsis for less cramped feel
- **Hidden send button when empty**: Send button now hidden (not just faded) when input is empty; appears with scale+opacity transition when content is typed or file attached
- **File-only send**: Users can attach and send files/images without any text; auto-generates "View the attached file" prompt when sending attachments alone

**Files changed:**

- `apps/ios/Todus/Todus/Features/AI/AIChatView.swift` — All five changes in inputSection, chatInputBox, toolbarContent, sendMessage(), ChatVoiceInputButton

## [2026-03-30] Enhancement — Resizable & movable AI assistant panels

Made both floating and side pane assistant panels user-resizable:

- **Floating panel resizable**: Bottom-right drag handle (min 320×400, max 700×900) with crosshair cursor
- **Floating panel movable**: Header drag gesture moves panel freely around the window
- **Side pane resizable**: Draggable divider replaces static Divider (min 280px, max 600px) with resize cursor
- **Self-managed sizing**: Floating panel manages its own frame via internal `floatingSize` state; MacRootView no longer imposes fixed dimensions
- **Icon consistency**: AssistantButton uses `sparkles` icon matching iOS

**Files changed:**

- `MacAssistantPanel.swift` — Added `floatingSize`, `floatingOffset`, resize handle overlay, `.frame()` and `.offset()` modifiers
- `MacRootView.swift` — Added `sidePaneWidth` state, draggable resize divider with `NSCursor.resizeLeftRight`, removed fixed floating frame

## [2026-03-30] Fix — Clear remaining iOS and macOS build blockers

Resolved the latest Xcode compile errors in both native targets:

- marked the shared AI card date formatter as `nonisolated(unsafe)` so `ISO8601DateFormatter` stops tripping Swift 6 sendability checks
- fixed the voice input controller by storing its completion handler on the main actor and treating `AudioPlayerManager` as the failable optional it is
- removed the `selection` shadowing bug in the macOS root view so the home view can navigate the sidebar state correctly
- verified both targets build successfully with `xcodebuild` for the iOS simulator and macOS

**Files changed:**

- `apps/ios/Todus/Todus/Features/AI/CardViews.swift`
- `apps/ios/Todus/Todus/Features/Voice/VoiceChatViewModel.swift`
- `apps/ios/Todus/Todus/Features/Voice/VoiceInputButton.swift`
- `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`
- `apps/macos/TodusMac/App/MacRootView.swift`
- `apps/ios/Todus/status_ios.md`
- `apps/ios/Todus/status_macos.md`

## [2026-03-30] Enhancement — macOS AI Assistant visual parity with iOS

Second pass to match the iOS AIChatView pixel-for-pixel. Key additions:

- **Page context chip**: Blue pill (e.g. "🏠 Home ×") showing current view, removable by user
- **Context-aware suggestions**: Suggestion pools change per active page (Home/Tasks/Email/Calendar) matching iOS
- **Show more / Show less**: Expandable suggestions with shuffle-on-refresh, matching iOS behavior
- **Prompt library**: Popover with 12 categorized prompt templates (Writing, Planning, Email, etc.)
- **Voice input (mic)**: Full speech-to-text via macOS Speech framework + AVAudioEngine, matching iOS VoiceInputButton
- **Attachment button (+)**: File picker for attaching documents, with removable pill previews
- **Thumbs up/down feedback**: Added to action row matching iOS
- **Animated sparkle icon**: Rotating gradient sparkles icon matching iOS AnimatedSparkleIcon
- **Reasoning box**: Collapsible thinking box with auto-expand/collapse matching iOS ReasoningBox
- **Darker background**: Panel background now matches iOS dark theme
- **Rounded input box**: Input section wrapped in rounded surface card matching iOS chatInputBox design
- **Draft persistence**: Input text saved/restored via UserDefaults
- **Rename conversation**: Alert dialog for renaming chat title
- **Microphone permissions**: Added NSMicrophoneUsageDescription + NSSpeechRecognitionUsageDescription to Info.plist
- **Wider panel**: Floating 400×560 (was 380×520), side pane 380 (was 360) for more breathing room

**Files changed:**

- `MacAssistantPanel.swift` — Complete rewrite with ~900 lines of iOS-parity UI
- `MacRootView.swift` — Passes `selection` to panel for page context chip
- `Info.plist` — Added microphone and speech recognition usage descriptions

## [2026-03-30] Feature — macOS AI Assistant with full iOS feature parity

Complete rewrite of the macOS AI assistant to achieve 100% feature parity with the iOS app. Replaced the placeholder `.sheet()` modal with an inline chat panel supporting two display modes.

### Display Modes

- **Floating mode**: draggable overlay window (380×520) anchored bottom-right, stays open while navigating
- **Side pane mode**: docked 360px panel on the right edge, integrated into the main layout
- Toggle between modes via header button; ⌘L toggles open/close; FAB hides when panel is open

### Streaming & Tool Calls (iOS parity)

- Full SSE streaming with 40ms token batching for smooth typewriter animation
- Tool call processing: `create_task`, `update_task`, `delete_task`, `create_calendar_event`, `send_email`
- Task CRUD mutations applied directly to SwiftData via ModelContext
- Calendar events created via CalendarService actor
- Email sending via EmailService

### Web Search & Reasoning

- `search_status` SSE events show animated search indicator with rotating status text
- `sources` SSE events rendered as clickable source chips (opens URL in browser)
- `reasoning` / `reasoning_done` events displayed in collapsible disclosure group

### Conversation History

- Full conversation persistence to UserDefaults (50-conversation cap)
- History popover for browsing and resuming past conversations
- New conversation button, auto-save on panel hide

### UI Polish

- Inline-only markdown during streaming for performance, full CommonMark after streaming ends
- Action row per message: retry (removes dependent turns) + copy with checkmark feedback
- Model picker (gpt-4.1, o4-mini, gpt-4.1-mini) in header
- Mutation chips with color-coded action badges (green=create, blue=update, red=delete)
- Suggestion chips for empty state quick prompts

**Files created:**

- `apps/macos/TodusMac/Services/AI/MacAIChatService.swift` — full AI chat service with SSE, tool calls, history, retry
- `apps/macos/TodusMac/Views/AI/MacAssistantPanel.swift` — polished chat panel with dual display modes

**Files changed:**

- `apps/macos/TodusMac/App/MacAppServices.swift` — added `aiChatService` with calendarService dependency
- `apps/macos/TodusMac/App/MacRootView.swift` — replaced `.sheet()` with inline floating/sidepane panel
- `apps/macos/TodusMac.xcodeproj/project.pbxproj` — registered new files and groups

## [2026-03-30] Fix — Harden iOS AI chat history replay and UI-spec rendering

Resolved three correctness issues in the native iOS AI chat flow that surfaced during code review.

- saved AI conversations now persist mention references alongside message text, so reopened chats keep task/thread/event IDs available for follow-up turns
- retrying an older assistant response now removes later dependent turns before replaying, preventing contradictory branched history from being sent back to the backend
- assistant replies that only contain a `ui-spec` block now clear the raw fenced JSON from the visible message body and render only the generated UI

**Files changed:**

- `apps/ios/Todus/Todus/Domain/AIChatConversation.swift`
- `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`
- `apps/ios/Todus/Todus/Features/AI/AIChatMessage.swift`
- `apps/ios/Todus/TASK.md`
- `apps/ios/Todus/plan.md`

## [2026-03-30] Fix — Stabilize iOS AI chat history loading, duplication, and spec-only actions

Resolved a second set of AI chat state issues found during follow-up review.

- loading a saved chat now cancels any active AI stream first, so the newly loaded conversation does not inherit stale streaming/error state from the previous request
- duplicating a conversation now preserves the full in-memory message models, including mentions and assistant metadata, and leaves the duplicate marked unsaved so it can autosave normally
- assistant action rows now remain visible for spec-only replies that render native UI cards, while the copy action is disabled when there is no plain text payload to copy

**Files changed:**

- `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`
- `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`
- `apps/ios/Todus/TASK.md`
- `apps/ios/Todus/plan.md`

## [2026-03-30] Fix — Restore iOS AI chat endpoint and message actions

Resolved the current native iOS AI chat regression where every prompt failed immediately with `⚠️ Server error (404).`

- updated the iOS AI chat and notification digest clients to call `/api/ai/chat`, matching the backend router mount
- added targeted assistant-message retry so retry replaces the tapped reply in place instead of appending a duplicate turn
- stabilized the assistant action row so the copy button always uses primary text color and keeps a fixed width while swapping between copy and checkmark states
- preserved existing streaming, search, reasoning, and tool-call handling in the AI chat service

**Files changed:**

- `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`
- `apps/ios/Todus/Todus/Services/Notifications/NotificationDigestService.swift`
- `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`
- `apps/ios/Todus/TASK.md`
- `apps/ios/Todus/plan.md`

## [2026-03-29] Fix — Restore iOS AI spec rendering and calendar build

Resolved the current Xcode build failures in the native iOS app:

- replaced the recursive `some View` renderer in `ChatUISpecView` with `AnyView`-based recursion so SwiftUI type inference no longer feeds itself
- marked `EKWrapper` as `@unchecked Sendable` to satisfy Swift 6 concurrency checking when calendar event wrappers move from the background EventKit fetch back to the main thread
- verified the project builds successfully with `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -destination 'generic/platform=iOS Simulator' build`

**Files changed:**

- `apps/ios/Todus/Todus/Features/AI/ChatUISpecView.swift`
- `apps/ios/Todus/Todus/Features/Calendar/EKWrapper.swift`
- `apps/ios/Todus/status_ios.md`
- `apps/ios/Todus/TASK.md`

## [2026-03-29] Feature — Native macOS shell scaffold replaces Electron wrapper

### Summary

Replaced the legacy Electron-based `apps/macos` wrapper with a standalone SwiftUI macOS app scaffold driven by XcodeGen.

This first native macOS pass is intentionally shell-only:

- added a single-window `TodusMac` app
- added `NavigationSplitView` shell layout with a custom sidebar
- added placeholder panes for Home, Tasks, Email, and Calendar
- added a SwiftUI content header with notification, menu, edit, and search affordances
- added a floating Assistant button with a placeholder sheet
- added placeholder account menu and Settings modal
- updated canonical docs to describe macOS as a native SwiftUI target
- updated macOS status tracking to reflect shell completion and the remaining Xcode license blocker for CLI build verification

**Files changed:**

- `apps/macos/README.md`
- `apps/macos/project.yml`
- `apps/macos/TodusMac/App/TodusMacApp.swift`
- `apps/macos/TodusMac/App/MacRootView.swift`
- `apps/macos/TodusMac/App/MacSidebarView.swift`
- `apps/macos/TodusMac/App/MacContentHeaderView.swift`
- `apps/macos/TodusMac/App/AssistantButton.swift`
- `apps/macos/TodusMac/Resources/Info.plist`
- `AGENTS.md`
- `APPS_ARCHITECTURE.md`
- `docs/architecture/README.md`
- `docs/architecture/APPS_ARCHITECTURE.md`
- `docs/development/SCRIPTS_GUIDE.md`
- `docs/testflight-checklist.md`
- `docs/guides/AGENTS.md`
- `apps/ios/Todus/status_macos.md`

## [2026-03-29] Fix — Restore GenerativeUI files to Xcode build sources

ChatUISpec.swift, ChatUISpecView.swift, and CardViews.swift were removed from the Xcode project (PBXBuildFile, PBXFileReference, PBXGroup, PBXSourcesBuildPhase) during prior cleanup of the GenerativeUI subdirectory, but the files still exist at Features/AI/ and are actively referenced by AIChatMessage.swift, AIChatView.swift, and AIChatService.swift. Re-added all three files to the project to fix "Cannot find type" build errors.

**Files changed:** `apps/ios/Todus/Todus.xcodeproj/project.pbxproj`

## [2026-03-29] Fix — iOS Xcode build environment reset for CalendarKit registration hangs

### Summary

Investigated repeated Xcode GUI hangs around:

- `RegisterExecutionPolicyException ... CalendarKit.o`
- `RegisterExecutionPolicyException ... CalendarKit_CalendarKit.bundle`

This was not caused by CalendarKit source code itself. The package is a simple SwiftPM dependency with no nested package dependencies or binary artifacts. A clean rebuild showed the hang correlated with local Xcode/macOS environment state after manual cache cleanup.

**Root cause found:**

- Xcode had been configured to use custom build output paths:
  - `~/XcodeDerivedData/Todus`
  - `~/Desktop/Build/Intermediates.noindex`
- After caches were manually deleted, those non-default locations interacted badly with execution-policy registration (`syspolicyd`) and later with a corrupted `XCBuildData/build.db`.

**Fixes applied:**

- Reset Xcode build location preferences back to default DerivedData behavior
- Cleared Todus DerivedData and SwiftPM caches
- Re-resolved package dependencies so CalendarKit was checked out fresh
- Regenerated `apps/ios/Todus/Todus.xcodeproj` from `apps/ios/Todus/project.yml`
- Excluded `**/archived/**` from the iOS target so clean builds do not pull in stale duplicate files like `Navigation/archived/CustomTabBar.swift`

**What this proved:**

- `RegisterExecutionPolicyException` for CalendarKit now completes in a clean isolated build path
- The remaining failures after the reset were ordinary project/source issues surfaced by a true clean build, not CalendarKit registration hangs

**Files changed:**

- `apps/ios/Todus/project.yml`
- `apps/ios/Todus/Todus.xcodeproj/project.pbxproj`
- `apps/ios/Todus/status_ios.md`

## [2026-03-29] Cross-platform code quality fixes — iOS, web, gitignore

### Summary

Batch of code quality fixes across iOS and web apps:

- **`.gitignore`**: Added `.deriveddata/` and `DerivedData/` to prevent Xcode build artifacts from being committed
- **`Info.plist`**: Added standard bundle identification keys (CFBundleIdentifier, CFBundleVersion, etc.) using build setting variables
- **`project.pbxproj`**: Removed stale build references for deleted files (CardViews.swift, ChatUISpec.swift, ChatUISpecView.swift)
- **`GmailOnboardingView`**: Updated copy to include explicit permission disclosure ("Grant access to...")
- **`EmailInboxView`**: Fixed misleading empty state text — replaced "Pull down to refresh" with "Tap Refresh" since pull-to-refresh is only on the thread list
- **`SettingsView`**: Updated Email & AI section footer to describe all controls in the section
- **`MainTabView`**: Added `.snappy` animation to requestCreateSheet handler to match tab bar behavior
- **`AuthService`**: Reset `isSessionExpired` in `signOut()` to prevent stale banner after sign-out
- **`en.json`**: Added `common.actions.unsavedChanges` i18n key
- **`general/page.tsx`**: Replaced hardcoded "Unsaved changes" with i18n call
- **`mail.tsx`**: Added `aria-label="Compose email"` to floating compose button for screen reader accessibility
- **`signatures/page.tsx`**: Replaced hardcoded title/description with i18n message calls

**Files changed:**

- `.gitignore`
- `apps/ios/Todus/Todus.xcodeproj/Info.plist`
- `apps/ios/Todus/Todus.xcodeproj/project.pbxproj`
- `apps/ios/Todus/Todus/App/GmailOnboardingView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`
- `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
- `apps/ios/Todus/Todus/Services/Auth/AuthService.swift`
- `apps/mail/messages/en.json`
- `apps/mail/app/(routes)/settings/general/page.tsx`
- `apps/mail/components/mail/mail.tsx`
- `apps/mail/app/(routes)/settings/signatures/page.tsx`

---

## [2026-03-29] iOS UX Fixes — Auth links, onboarding copy, action grouping, create sheet, search indicator, empty states, send error, session confirm, AI detent, settings regrouping

### Summary

Batch of iOS UX improvements across 9 files:

- **I13 AuthView**: Terms of Service and Privacy Policy are now tappable links opening todus.app/terms and todus.app/privacy
- **I2 GmailOnboardingView**: Updated copy to be benefit-oriented ("See your inbox, reply to emails...")
- **I3 EmailThreadView**: Added visual divider between non-destructive (star, unread) and destructive (archive, trash) action buttons
- **I5 HomeView + AppServices + MainTabView**: Events and Tasks "+" buttons now open CreateSheet directly instead of navigating to another tab
- **I8 EmailInboxView**: Added inline "Searching..." indicator when search is in progress
- **I11 EmailInboxView**: Improved empty state with refresh button and better copy
- **I10 EmailComposeView**: Added error alert when email send fails
- **I12 MainTabView**: Session expired banner now shows confirmation dialog before signing out
- **I15 MainTabView**: AI chat sheet uses .medium detent instead of .fraction(0.5)
- **I9 SettingsView**: Merged 9 sections into 4 logical groups (Preferences, Email & AI, Notifications & Privacy, About)

**Files changed:**

- `apps/ios/Todus/Todus/Features/Auth/AuthView.swift`
- `apps/ios/Todus/Todus/App/GmailOnboardingView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift`
- `apps/ios/Todus/Todus/Features/Home/HomeView.swift`
- `apps/ios/Todus/Todus/App/AppServices.swift`
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailComposeView.swift`
- `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`

## [2026-03-29] Fix — Buffer early WebSocket messages in voice proxy

### Summary

In the `/ai/voice-ws` WebSocket proxy, `serverWs.accept()` was called before the upstream Gemini connection was established and forwarding handlers attached. Any client messages arriving during the Gemini `fetch()` would be silently dropped (e.g. the setup config message). Added an early-buffering message handler that queues messages until upstream is ready, then flushes them in order before switching to direct forwarding.

**Files changed:**

- `apps/server/src/routes/ai.ts` — Attach buffering handler immediately after `serverWs.accept()`, flush + switch to direct forwarding after `upstream.accept()`

## [2026-03-29] Fix — Persist Mention IDs Across Follow-up Chat Turns

### Summary

Mentions (e.g. `@thread X`, `@task Y`) only resolved for the turn they were inserted in. The underlying entity IDs were stored in a transient `currentTurnMentions` array that was cleared after each stream, while prior messages were serialized as plain text. A multi-turn flow like "summarize @thread X" → "reply to it" would lose the resolved thread ID on the second turn.

**Fix:** Added a `mentions: [RichInputMentionRef]` property to `AIChatMessage` so each user message persists its mention refs. `buildPayload` now collects de-duplicated mentions from ALL user messages in the conversation history (not just the current turn), ensuring entity IDs remain resolvable across follow-up turns.

**Files changed:**

- `apps/ios/Todus/Todus/Features/AI/AIChatMessage.swift` — Added `mentions` property and init parameter
- `apps/ios/Todus/Todus/Services/AI/AIChatService.swift` — Store mentions on user message at send time; `buildPayload` collects mentions from all user messages with de-duplication

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

## [2026-03-29] Voice Chat Bug Fixes — Double Disconnect, Data Race, Robustness

### Summary

Fixed two critical bugs and multiple robustness issues in the Live Voice Chat feature:

**Bug 1 — Double disconnect duplicates chat messages:** Both Close/End Call buttons called `disconnect()` then `dismiss()`, triggering `onDisappear` which called `disconnect()` again. Without an early-return guard, `finalizedTurns` was iterated twice, duplicating all voice messages in chat history. Fix: added `guard connectionState != .disconnected` at top of `disconnect()` and clear `finalizedTurns` after writing.

**Bug 2 — Data race on `isMicMuted`:** The `@MainActor`-isolated `isMicMuted` was read from the audio processing thread in the `installTap` callback and the DispatchSource timer. Fix: added a lock-protected `_micMutedAtomic` Bool that audio threads read, synced from `toggleMute()`.

**Additional fixes:**

- Simplified redundant `connect()` guard that only matched `.failed("")` instead of any `.failed` case
- Provider is now disconnected if audio capture setup fails after a successful connection
- `sendText()` now checks connection state before sending
- Tool call status tracking prevents concurrent tool calls from clobbering each other's UI status
- `sendToolResponse` errors are now logged instead of silently swallowed
- AVAudioConverter input block correctly returns `.noDataNow` after first data supply
- AudioPlayerManager: force-unwrap replaced with guard-let + fatalError; `isPlaying` getter synchronized on audioQueue; playback state resets when scheduled buffers complete naturally
- GeminiLiveProvider: event stream recreated on `connect()` (no longer single-use); URLSession stored and invalidated on disconnect; send functions throw `.notConnected` instead of silent return; receive loop error handler cleans up WebSocket state; `goAway` emits `.disconnected` (no auto-reconnect exists); `sendJSON` throws on nil webSocketTask; setup failure cleans up connection
- Voice tool calls now respect `aiCanWriteTasks` permission (matches text chat path)
- Tool result JSON built with `JSONEncoder` instead of string interpolation (prevents breakage from special characters in task titles)
- Calendar event creation errors propagated instead of silently swallowed
- `shouldSearchWeb()` evaluates time-sensitive keywords before short-command check (so "weather today" triggers search)
- Added `:focus-visible` keyboard focus styles for `.editor-suggestion-item` (WCAG 2.1 AA accessibility)

### Updated Files

- `apps/ios/Todus/Todus/Features/Voice/VoiceChatViewModel.swift` — disconnect guard, clear finalizedTurns, thread-safe mic flag, connect guard simplification, audio capture failure cleanup, sendText connection check, tool call tracking, converter fix
- `apps/ios/Todus/Todus/Services/Voice/AudioPlayerManager.swift` — safe init, synchronized isPlaying, buffer completion tracking
- `apps/ios/Todus/Todus/Services/Voice/GeminiLiveProvider.swift` — reusable event stream, URLSession lifecycle, throw on not-connected, receive loop cleanup, goAway state fix, sendJSON guard
- `apps/ios/Todus/Todus/Services/AI/AIChatService.swift` — aiCanWriteTasks check, encodeToolResult helper, calendar error handling
- `apps/server/src/routes/ai.ts` — shouldSearchWeb ordering fix
- `apps/mail/components/create/prosemirror.css` — focus-visible keyboard accessibility

### Skipped (verified not real bugs)

- VoiceTokenService race condition: class is `@MainActor`, so calls are serialized by the actor executor
- Raw API key in `/ai/voice-token`: Gemini Live requires direct client WebSocket — no way to proxy bidirectionally without a full relay server

## [2026-03-28] iOS compose mention follow-up fixes

### Summary

Reviewed the current iOS mention/slash-command compose changes and fixed two issues that were still present in the live code: email compose body focus was no longer wired to the existing `focusedField` state, and person mention suggestions could surface a different top-10 subset between runs because they were truncated before applying a stable sort.

### Updated Files

- `apps/ios/Todus/Todus/Features/Email/EmailComposeView.swift` — restored body-editor focus by passing explicit focus state into `RichComposerInput`, and sorted grouped senders by a stable name/email key before `prefix(10)`.
- `apps/ios/Todus/Todus/Features/Tasks/CaptureComposer.swift` — added optional focus control to `RichComposerInput` / `PasteHandlingTextInput` while preserving default auto-focus behavior for other existing callers.

### User-facing impact

- Opening compose now correctly places the keyboard in the body when `To` and `Subject` are already populated.
- Person mention suggestions in compose now remain stable and predictable across launches and rebuilds.

## [2026-03-28] Live Voice Chat — Gemini Live API Integration

### Summary

Production-quality bidirectional voice chat with AI assistant using Gemini Live API. Provider-agnostic architecture (protocol abstraction for future OpenAI Realtime support). No API keys in the iOS binary — backend mints short-lived tokens. Full tool call support (create tasks, send emails, create calendar events) during voice sessions.

### Backend (`apps/server/src/routes/ai.ts`)

- Added `POST /ai/voice-token` endpoint: returns `GOOGLE_GENERATIVE_AI_API_KEY` with 5-minute TTL and model name, gated by Bearer auth

### iOS — New Files

- `Services/Voice/VoiceProvider.swift` — Protocol + enums (`VoiceConnectionState`, `TranscriptRole`, `VoiceSessionEvent`) + `VoiceSessionConfig` struct
- `Services/Voice/GeminiLiveProvider.swift` — WebSocket implementation using native `URLSessionWebSocketTask`, handles Gemini Live bidirectional protocol
- `Services/Voice/VoiceTokenService.swift` — Fetches and caches tokens from backend
- `Services/Voice/AudioPlayerManager.swift` — Plays PCM16 24kHz audio chunks via `AVAudioEngine` + `AVAudioPlayerNode`
- `Features/Voice/VoiceChatViewModel.swift` — @Observable ViewModel: manages provider, audio capture (PCM16 16kHz), transcript state, tool call routing
- `Features/Voice/VoiceChatModalView.swift` — Full-screen modal: transcript area, animated listening/speaking indicator, mic mute/end call controls

### iOS — Modified Files

- `AIChatService.swift` — Added `appendVoiceExchange()`, `buildSystemPromptForVoice()`, `processVoiceToolCall()`, `voiceToolDeclarations()`
- `AIChatMessage.swift` — Added `MessageSource` enum (.text/.voice) with `source` property
- `AIChatView.swift` — Added waveform button (AI gradient) in both expanded/compact chat input modes + `.fullScreenCover` for voice modal
- `AppServices.swift` — Added `VoiceTokenService` registration

### Architecture Notes

- Voice transcripts stay local in the modal; only finalized exchanges are written to main chat history on disconnect
- Tool calls route through existing `AIChatService` pipeline
- Audio: capture PCM16 @ 16kHz via AVAudioEngine → 100ms chunks → WebSocket; playback PCM16 @ 24kHz

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

## [2026-03-28] Comprehensive SEO Overhaul — From Zero to Indexed

### Summary

todus.app had zero Google-indexed pages. This overhaul adds all missing SEO infrastructure, creates competitor comparison pages and a blog for organic traffic, and enables pre-rendering so Google sees real HTML content.

### New Files

- `apps/mail/public/robots.txt` — Crawler directives (allow public, disallow /mail/, /settings/)
- `apps/mail/public/sitemap.xml` — All public URLs for search engine discovery
- `apps/mail/app/(full-width)/compare/[competitor]/page.tsx` — Data-driven comparison pages (vs Superhuman, Shortwave, Spark, Motion)
- `apps/mail/app/(full-width)/blog/index.tsx` — Blog index page
- `apps/mail/app/(full-width)/blog/[slug]/page.tsx` — Blog post pages with 3 initial SEO articles
- `SEO-AUDIT.md` — Full audit findings, implementation status, and content calendar

### Updated Files

- `apps/mail/lib/site-config.ts` — New title, description, Twitter cards, JSON-LD schemas (Organization, SoftwareApplication, FAQPage), 25+ target keywords
- `apps/mail/app/root.tsx` — Canonical URL, Twitter cards, keywords meta, robots meta, JSON-LD structured data, apple-touch-icon, preconnect/dns-prefetch
- `apps/mail/react-router.config.ts` — Pre-render 16 public pages for SEO (static HTML at build time)
- `apps/mail/app/routes.ts` — Added /compare/:competitor, /blog, /blog/:slug routes
- `apps/mail/app/(full-width)/about.tsx` — Page-specific SEO meta tags
- `apps/mail/app/(full-width)/pricing.tsx` — Page-specific SEO meta tags

### SEO Elements Added

- Title tag: "Todus — AI Email, Calendar & Tasks in One App"
- Meta description with value prop and YC credibility
- 25+ target keywords in meta tag
- Canonical URL on every page
- Open Graph tags (title, desc, image, dimensions, alt, site_name)
- Twitter/X Cards (summary_large_image)
- JSON-LD Organization schema
- JSON-LD SoftwareApplication schema
- JSON-LD FAQPage schema with 6 Q&As
- robots.txt with crawler directives
- sitemap.xml with all public URLs
- Pre-rendered HTML for all 16 public pages

### Verification

- Build succeeds: `pnpm --filter mail build` completes with all 16 pages pre-rendered
- Pre-rendered HTML verified to contain all meta tags, structured data, and visible content

---

## [2026-03-28] Cross-platform mentions and slash commands

### New Features

- **Shared mention model**: Added shared `MentionKind` / `MentionRef` types in `packages/shared` so web, server, and iOS use the same structured mention payload.
- **Server mention search**: Added `mentions.search` tRPC route for task, thread, and person lookup with grouped results and stable IDs. Event mentions remain feature-gated on web until a web provider exists.
- **AI mention context**: `/ai/chat` and the web agent route now accept optional `mentions` arrays and inject compact structured mention context into the current user turn before model execution.
- **Web TipTap mentions and slash commands**: The active shared editor hook now supports `@` mentions, `/` commands, human-readable mention chips, and per-surface command ordering for email compose and AI chat.
- **Web submit serialization**: Email compose now strips mention metadata to readable text before send; AI chat extracts mention refs separately and submits them as structured context.
- **iOS rich input**: Added a reusable `UITextView`-backed rich composer input with shared slash command definitions, inline mention highlighting, and reuse across task capture, email compose, and AI chat.
- **iOS mention-aware AI requests**: Native AI chat now collects mention refs and includes them in the backend payload alongside the visible user message.

### Architectural Notes

- **Shared slash semantics**: iOS task capture now derives slash actions from the same shared command model used by the new rich input surfaces instead of maintaining a one-off command list.
- **Compose signature command**: Email compose now supports `/signature` using the currently active native signature.

### Verification

- `pnpm --filter @zero/mail exec tsc --noEmit --pretty false` narrowed to the edited mail files reports no errors.
- `pnpm --filter @zero/server exec tsc --noEmit --pretty false` narrowed to the edited server files reports one pre-existing unrelated overload error in `apps/server/src/routes/agent/index.ts`.
- `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -configuration Debug -sdk iphonesimulator -derivedDataPath /tmp/todus-codex-derived-data build CODE_SIGNING_ALLOWED=NO` was started to validate the edited Swift files in an isolated build directory.

## [2026-03-27] iOS — Single `NotificationService`, action IDs aligned with `TodosApp`

### Bug Fix / Architecture

- **Removed duplicate `NotificationService`**: Only `Services/Notifications/NotificationService.swift` is compiled now; the old `Resources/NotificationService.swift` copy (different `Action` string constants) is deleted. Xcode file reference moved to `Services/Notifications/`. Action identifiers remain `TASK_COMPLETE` / `TASK_SNOOZE`, matching `UNNotificationAction` registration and `AppDelegate` in `TodosApp.swift`.
- **Merged behavior**: 1-hour-before-due scheduling, `TASK_REMINDER` category, async permission request before scheduling (from the former Resources implementation), plus `clearAll` / `cancel(withIdentifiers:)` helpers.

---

## [2026-03-27] iOS — Global search, task search bar visibility, touch targets, UI polish

### New Features

- **Global search sheet**: Magnifying glass button added as first item in `AppTopHeader` action pill. Opens a full-screen sheet (`GlobalSearchView`) that searches tasks (SwiftData), emails (in-memory threads), calendar events, and people — all local, no extra network calls. Tap results to deep-navigate.
- **Touch targets expanded**: Added `minTouchTarget()` extension (`frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())`) and applied to all small buttons across the app — search clear buttons, sort menu, email thread actions, board column controls, AI chat send/stop/config, voice buttons, attachment delete. Skipped dense equal-width rows (view mode picker, tab bar) to avoid conflicts.

### Bug Fixes / Visual Improvements

- **Task search bar visibility**: Changed background from `surfaceSecondary.opacity(0.55)` (nearly invisible) to `surfacePrimary` (full opacity), and border from `cardBorder` to `strongBorder` — clearly visible in both light and dark mode.
- **Avatar resized and made circular**: `AppTopHeader` avatar is now 34×34pt `Circle()` (was 40×40 `RoundedRectangle`), matching the height of the action pill beside it.
- **Calendar header overlap fixed**: `CalendarContainerView` now accepts `topInset: CGFloat` and applies it via `additionalSafeAreaInsets.top` on the `CalendarViewController`, pushing CalendarKit's scroll content below the SwiftUI `AppTopHeader` overlay.

### Files Changed

- `DesignSystem/AppTheme.swift` — minTouchTarget extension, avatar → circle, global search button + sheet in actionsPill
- `Features/Tasks/TasksTabView.swift` — search bar background/border fix + touch targets
- `Features/Search/GlobalSearchView.swift` — **NEW** — full global search sheet
- `Navigation/MainTabView.swift` — calendar header height measurement + topInset wiring
- `Features/Calendar/CalendarContainerView.swift` — `topInset` param + additionalSafeAreaInsets
- Multiple view files — `.minTouchTarget()` applied to small buttons

---

## [2026-03-27] iOS — AI-powered Notification Center

### New Feature

- **Notification Center sheet**: Tapping the bell icon in the app header now opens a notification center sheet (was: opened iOS system notification settings). The sheet shows an AI-generated digest of tasks due, upcoming calendar events, and important unread emails — grouped by type with priority indicators and tap-to-navigate actions.

### Architecture

- **NotificationDigestService** (`Services/Notifications/`): Sends local task/event/email data to `/ai/chat` with a specialized system prompt. Uses non-streaming mode for simpler JSON response parsing.
- **NotificationCenterView** (`Features/Notifications/`): SwiftUI sheet with loading skeleton, error/empty states, and grouped notification cards following existing HomeView design patterns.

### Files Changed

- `AppTheme.swift` — Bell button now opens NotificationCenterView sheet instead of system settings
- `NotificationDigestService.swift` — **NEW** — AI digest backend integration
- `NotificationCenterView.swift` — **NEW** — Notification center sheet UI

---

## [2026-03-27] iOS — Fix Gmail connection persistence + Connect/Permission view consistency

### Bug Fixes

- **Gmail connection not persisting after onboarding**: `GmailOnboardingView` now calls `emailService.checkConnection()` + `loadThreads()` after OAuth, so the email tab reflects the connected state immediately.
- **`hasConnection` default changed from `true` to `false`**: Prevents a brief flash of the thread list before `checkConnection()` runs on first load.

### Visual Consistency

- **EmailConnectView**: Rewritten to match `GmailOnboardingView` exactly — uses `GmailIconView(size: 88)` icon, `AppPrimaryButtonStyle()` button with `GmailIconView(size: 20)` inline, same spacing/typography.
- **CalendarPermissionView**: Rewritten to match onboarding styling — uses `AppleCalendarIconView(size: 88)` instead of generic SF Symbol, `AppPrimaryButtonStyle()` buttons, same layout pattern.

### Files Changed

- `GmailOnboardingView.swift` — Added `checkConnection()` + `loadThreads()` after successful OAuth
- `EmailConnectView.swift` — Full rewrite to match onboarding styling
- `CalendarPermissionView.swift` — Full rewrite to match onboarding styling
- `EmailService.swift` — `hasConnection` default changed from `true` to `false`

---

## [2026-03-27] iOS Tasks — Color System, Scroll Fix, Visual Overhaul

### Bug Fixes

- **Board column scroll**: Columns now have internal vertical `ScrollView` so card overflow scrolls instead of being clipped. Header stays sticky above the scroll area.

### Design Overhaul — All Task Views

- **Consistent tinted status system**: Todo = muted gray, Doing = muted blue, Done = muted green. Applied across board columns, table rows, list tags, and calendar headers.
- **Board columns**: Each column has a very subtle tinted background (0.025 opacity) and tinted border (0.08 opacity). Drop highlight intensifies the tint. Column gap tightened (12→10). Dashed add-task button at bottom.
- **Board cards**: Left-edge color indicator bar per status. Priority flag icons. Overdue dates in red, today in amber. Completed tasks show strikethrough with dimmed text. Thinner border (0.5px).
- **Table view**: Status column now shows colored pills with icon + text (tinted bg + border). Checkbox uses status tint color. Priority dot indicator. Color-coded due dates. Uppercase header labels. "Move to…" context menu added.
- **Calendar view**: Bucket headers now have colored icons (sun for Today, sunrise for Tomorrow, calendar for This Week) with tinted count badges. Each bucket has a unique warm→cool color progression.
- **List view (TaskRowView)**: Status tags now use tinted backgrounds matching their column color. Due date tags are color-coded (red=overdue, amber=today). Priority tags use colored flag icons. All tags use consistent 5pt radius with 0.5px tinted borders. Row corner radius refined (16→14).

### Files Changed

- `BoardView.swift` — Column gap 12→10
- `BoardColumnView.swift` — Vertical scroll for cards, sticky header, tinted column bg/border, dashed add-task button
- `BoardTaskCard.swift` — Left-edge color bar, priority flags, due date coloring, strikethrough for completed
- `TaskTableView.swift` — Colored status pills, priority dots, due date colors, uppercase header, "Move to…" context menu
- `CalendarTaskView.swift` — Colored bucket headers with icons, tinted count badges, warm→cool color progression
- `TaskRowView.swift` — Tinted status/due/priority tags, dimmed completed state, refined tag sizing

## [2026-03-27] iOS Board View — Drag/Drop, Inline Add, UI Polish

### Features

- **Drag & drop tasks between columns**: Drop destination with animated status change and visual drop highlight using column tint colors.
- **Tap column empty area to add task**: Tapping anywhere in a column's empty space opens an inline add field at the top of the card list.
- **+ button in column headers**: Quick-add button in the top-right of each column header, tinted with the column's accent color.
- **"Add task" button at column bottom**: Outlined button with muted column-tint border and text, matching each status's color identity.
- **Context menu "Move to…" submenu**: Board cards now have a status-change submenu in the long-press context menu for quick column moves.
- **`captureInStatus()` method**: New `TaskCaptureService` method for creating tasks directly into a specific status column with full sync.

### UI Polish

- **Column tint colors**: Each `TaskStatus` now has a subtle accent color (slate for Todo, blue for Doing, green for Done) and a status icon.
- **Tighter spacing**: Reduced column width (272→264), card padding (12→10/9), card corner radius (16→10), column corner radius (16→14).
- **Refined typography**: Smaller, denser text (13→12pt cards, 13→12pt headers), tighter tracking, softer foreground opacity.
- **Lighter column backgrounds**: Reduced from solid fill to 55% opacity for a more breathable look.
- **Removed heavy shadows**: Cards use clean border-only styling instead of glassCard with drop shadows.

### Files Changed

- `apps/ios/Todus/Todus/Domain/TaskStatus.swift` — Added `tintColor`, `systemImage` properties
- `apps/ios/Todus/Todus/Services/Tasks/TaskCaptureService.swift` — Added `captureInStatus()` method
- `apps/ios/Todus/Todus/Features/Tasks/BoardColumnView.swift` — Full rewrite with inline add, + button, add-task button, refined styling
- `apps/ios/Todus/Todus/Features/Tasks/BoardTaskCard.swift` — Refined styling, added "Move to…" context menu
- `apps/ios/Todus/Todus/Features/Tasks/BoardView.swift` — Tighter spacing (16→12 gap), removed tap-to-dismiss-keyboard gesture

## [2026-03-27] Mem0 Integration — Persistent AI Memory

### New Feature

- **`apps/server/src/lib/mem0.ts`** (NEW): Mem0 REST API client with multi-layer caching (in-memory → KV → API). Provides `addMemories`, `searchMemories`, `getAllMemories`, `getCachedMemories`, `preloadMemories`, `invalidateMemoryCache`, and `formatMemoriesForPrompt`.
- **`apps/server/src/env.ts`**: Added `MEM0_API_KEY` to `ZeroEnv` type. Set via Cloudflare dashboard secrets.
- **`apps/server/src/routes/ai.ts`**: Integrated Mem0 into `/ai/chat` (iOS flow). Injects cached memories into system prompt. Captures assistant response via TransformStream tee and stores conversation in Mem0 post-stream.
- **`apps/server/src/routes/agent/index.ts`**: Integrated Mem0 into ZeroAgent (web flow). Preloads memories on WebSocket connect (background). Injects cached memories into system prompt (0ms). Stores conversation in Mem0 after response (fire-and-forget).

### Architecture

- **Zero latency**: Memories are preloaded on WebSocket connect / KV-cached. Hot path reads are 0ms (in-memory) or <5ms (KV). No Mem0 API calls block the user.
- **Cross-platform**: Both web and iOS share the same `user_id` (Better Auth user.id), so memories cross-pollinate.
- **Graceful degradation**: All Mem0 calls are try/catch wrapped. If Mem0 is down or unconfigured, AI works normally without memory.
- **No iOS changes needed**: Backend handles all Mem0 integration server-side.

### Setup Required

- Add `MEM0_API_KEY` as a Cloudflare secret (dashboard) and in `.env` for local dev.
- Sign up at https://app.mem0.ai to get an API key.

---

## [2026-03-27] Open source — secret hygiene & CI

### Security (contributor-facing)

- **Audited repo**: No real API keys or OAuth secrets found in tracked source; secrets belong in `.env` / `.dev.vars` / `wrangler secret` (all gitignored or dashboard-only).
- **`apps/server/wrangler.jsonc` (local)**: Removed numeric placeholders for `ELEVENLABS_API_KEY` and `VOICE_SECRET` (empty in `vars`); clarified dev JWT placeholder string. Added comment that real secrets must not live in committed `vars`.
- **`apps/server/src/env.ts`**: `JWT_SECRET` / `ELEVENLABS_API_KEY` typings widened to `string` (no fake literals).
- **`.gitignore`**: Ignore common credential filename patterns (`*credentials*.json`, Google service account blobs, etc.).
- **`SECURITY.md`**: Guidelines for reporting issues, forks, and never committing secrets.
- **`.github/workflows/gitleaks.yml`**: Gitleaks on pull requests.

---

## [2026-03-27] iOS Code Review — View Layer Fixes (Batch 2)

### Bug Fixes & Improvements

- **CalendarViewController.swift**: Added `inFlightDates` Set to prevent duplicate background EventKit fetches for the same day during rapid scrolling.
- **EmailConnectView.swift**: Added `@State isLoading` and `errorMessage`, wrapped Task in do-catch, disabled button while loading.
- **EmailRowView.swift**: Replaced hardcoded `Color.blue` with `AppTheme.accentBlue` for the unread indicator. Added combined accessibility label.
- **BoardView.swift**: Added `taskChangeSignature` computed property to detect status-only changes that `@Query` `onChange(of:)` misses.
- **CustomTabBar.swift** (active): Removed ineffective `.tracking()` modifier from Image views (only works on Text). Removed unused `iconTracking` constant.
- **TaskDetailSheet.swift**: Pass trimmed folder name to `createFolder`. Added `.accessibilityLabel("Create folder")` to the create-folder button.
- **TaskRowView.swift**: Increased checkbox tap target from 36x36 to 44x44pt per Apple HIG (visual icon stays at 18pt).
- **CalendarPermissionView.swift**: Updated Settings path from "Privacy → Calendars" to "Privacy & Security → Calendars".
- **SenderAvatarView.swift**: Changed `.task { urlIndex += 1 }` in failure case to `.onAppear` to prevent re-run loops. Reordered `fetchCandidateURLs` to prioritize backend-resolved URLs over local fallbacks.
- **AIChatView.swift + AIChatService.swift**: Retry button now actually replays the last user message via new `retry()` method instead of just clearing the error.
- **Archived CustomTabBar.swift**: Added accessibility labels to AI/create action buttons and tab buttons. Fixed `glassEffect(in:)` → `glassEffect(.regular, in:)` to match correct iOS 26 API. Removed ineffective `.tracking()` from Image views.

### Files Changed

- `Features/Calendar/CalendarViewController.swift`
- `Features/Calendar/CalendarPermissionView.swift`
- `Features/Email/EmailConnectView.swift`
- `Features/Email/EmailRowView.swift`
- `Features/Email/SenderAvatarView.swift`
- `Features/Tasks/BoardView.swift`
- `Features/Tasks/CustomTabBar.swift`
- `Features/Tasks/TaskDetailSheet.swift`
- `Features/Tasks/TaskRowView.swift`
- `Features/AI/AIChatView.swift`
- `Services/AI/AIChatService.swift`
- `Navigation/archived/CustomTabBar.swift`

---

## [2026-03-27] iOS Code Review Follow-up Fixes

### Bug Fixes & Hardening

- **AppServices.swift**: Persist migrated signatures to UserDefaults after legacy migration (prevents re-migration on every launch). Added logging for JSONEncoder failures in signatures didSet.
- **TodosApp.swift**: Moved `appDelegate.modelContainer` assignment into `initializeApp()` before @State properties are set, eliminating notification race condition. Replaced `try?` with `do/catch` + logging for context.save() and notification scheduling.
- **EmailModels.swift**: Replaced `UUID().uuidString` fallback in EmailAttachment with deterministic ID based on filename+size. Changed date parsing fallback from `Date()` to `Date.distantPast` with logging.
- **TodosAPIClient.swift**: Added missing `EmptyResponse` struct. After successful 401 silent refresh, requests now retry automatically instead of throwing.
- **AuthService.swift**: Converted `userName`/`userImage` from computed to stored properties with Keychain-syncing didSet. Added HTTP status check in `fetchUserProfile()` before parsing JSON.
- **TaskCaptureService.swift**: Reschedules notification when transitioning back to `.todo`. Cancels notification on `.done` in `updateTaskDetails()`. Schedules notification after enrichment applies a parsed due date.
- **NotificationService.swift**: `scheduleTaskReminder` now properly checks/requests authorization before scheduling notifications.

### Files

- `App/AppServices.swift` — signature migration persistence + error logging
- `App/TodosApp.swift` — notification race fix + error logging
- `Domain/EmailModels.swift` — deterministic attachment IDs + date fallback
- `Services/API/TodosAPIClient.swift` — EmptyResponse struct + retry-after-refresh
- `Services/Auth/AuthService.swift` — stored userName/userImage + HTTP status check
- `Services/Tasks/TaskCaptureService.swift` — notification lifecycle consistency
- `Resources/NotificationService.swift` — async authorization check

## [2026-03-27] iOS Settings — Email Signatures sub-page

### Feature: Full Signature Management

- **`SignaturesView`**: List showing all signatures with a checkmark on the active one. "None" row at top to disable signatures. Swipe-to-delete on each row. "+" toolbar button to create new. Each row navigates to the editor.
- **`SignatureEditorView`**: Name field + TextEditor for body + "Use as active signature" toggle + Delete button. Presented as a sheet for new signatures, pushed page for editing.
- **SettingsView**: Replaced the signature toggle + inline textfield with a `NavigationLink` to `SignaturesView`. Shows the active signature name (or "Off") as the row's value hint.
- **AppServices**: `signatures: [EmailSignature]` (JSON-persisted) + `selectedSignatureID: UUID?` + `activeSignature` computed property. Old `signatureEnabled`/`signatureText` properties preserved as backward-compat computed properties. Migration: existing single-text signature is imported as a "Default" signature on first launch with new version.
- **`EmailSignature` model**: `Codable + Identifiable + Sendable` struct in `Domain/EmailModels.swift`.

### Files

- `Domain/EmailModels.swift` — EmailSignature struct
- `App/AppServices.swift` — signatures/selectedSignatureID storage + migration
- `Features/Settings/SignaturesView.swift` — NEW (SignaturesView + SignatureEditorView)
- `Features/Settings/SettingsView.swift` — NavigationLink in email section
- `Todus.xcodeproj/project.pbxproj` — SignaturesView.swift registered

## [2026-03-27] iOS Splash screen redesign + brand icon fixes

### Splash Screen

- **Before**: Plain "Todus" text + spinner — no visual identity.
- **After**: Branded rounded-square app icon mark (checklist SF Symbol, 96pt) + "Todus" title (rounded bold) + spinner below. (`TodosApp.swift`)

### Brand Icon Fixes

- **AppleRemindersLogo clipping**: Previous `rowSpacing = h * 0.27` caused total content (1.14h) to overflow the frame, clipping the orange 3rd row. Reduced to `h * 0.11`; all 3 rows now fit at every size. (`BrandIcons.swift`)
- **AppleRemindersIconView**: Refactored to use `AppIconContainer` (same pattern as GmailIconView) — white rounded-rect background with proper breathing room. No more stretching to fill the frame.
- **AppIconContainer padding**: Inner icon frame reduced from `size * 0.72` to `size * 0.62` — ~19% padding on each side so icons feel airy.

### Files

- `apps/ios/Todus/Todus/App/TodosApp.swift` — branded splash
- `apps/ios/Todus/Todus/DesignSystem/BrandIcons.swift` — spacing fix, padding fix, AppleRemindersIconView refactor

## [2026-03-27] iOS — Fix 9s Startup Black Screen & Runtime Hangs

### Startup Black Screen Fix (CRITICAL)

- **TodosApp**: Deferred `AppServices` and `ModelContainer` initialization from synchronous `init()` to async `.task` context. Shows a branded splash screen immediately while services initialize in the background. Previously all 12+ services + SwiftData schema reconciliation ran synchronously before the first frame, causing a 9+ second black screen.
- **AIChatService**: Deferred `loadPersistedConversations()` (JSON deserialization from UserDefaults) to an async Task instead of running synchronously during init.

### Runtime Hang Fixes (from earlier session)

- Cached expensive computed properties (`buckets`, `tasksDueToday`, `filteredThreads`, `visibleTasks`, `tasksByStatus`) across 5 views to prevent recalculation on every body evaluation.
- Parallelized startup operations in RootView (auth upgrade + reminders setup).
- Fixed settings sheet binding with proper `@Bindable` pattern.
- Batched email thread fetches from 30 simultaneous to groups of 8.
- Fixed `EmailMessage`/`EmailAttachment` `Codable` → `Decodable`, added `Equatable` to `EmailThread`.

## [2026-03-27] iOS — Swift 6 concurrency build fixes (Todus)

### Fixed (Xcode / Swift 6)

- **`TodosApp.swift`**: Removed ineffective `@preconcurrency` on `UNUserNotificationCenterDelegate`. Snooze handling now uses a `Sendable` `SnoozeContentSnapshot` and rebuilds `userInfo` as `["taskID": taskIDString]` on the main actor (avoids sending `UNNotificationContent` / non-Sendable dictionaries across isolation).
- **`CalendarViewController.swift`**: EventKit access completions use a `@Sendable` closure that only schedules `Task { @MainActor [weak self] in ... }`, fixing `EKEventStoreRequestAccessCompletionHandler` data-race diagnostics.
- **`SenderAvatarView.swift`**: Initials avatar background color no longer uses `String.hashValue` (unstable across launches). Uses the same deterministic UTF-16 / JS `<<` algorithm as web `getAvatarColorIndex` in `bimi-avatar.tsx`.
- **`Services/Notifications/NotificationService.swift`**: Snooze now schedules via `enqueueTaskReminder(fireDate:)` at `now + 1h` instead of a synthetic `dueDate` passed through `scheduleTaskReminder` (avoids confusing stacked offsets; behavior unchanged).

### Files

- `apps/ios/Todus/Todus/App/TodosApp.swift`
- `apps/ios/Todus/Todus/Features/Calendar/CalendarViewController.swift`
- `apps/ios/Todus/Todus/Features/Email/SenderAvatarView.swift`
- `apps/ios/Todus/Todus/Services/Notifications/NotificationService.swift`

---

## [2026-03-27] PRD rewrite + iOS feature implementation (Phases 1–6)

### Documentation

- **PRD.md rewritten** as pure product spec — removed all architecture/code, added User Flows, Empty & Error States, Notifications, AI Interaction Model, Settings Screen Spec, Database Schema Revisions sections
- **AGENTS.md rewritten** from scratch — agent-agnostic architecture reference for all AI coding agents (Claude, Cursor, Gemini, etc.)
- **CLAUDE.md updated** — added iOS app detail (services layer, auth flows, data layer), fixed auth providers list
- **APPS_ARCHITECTURE.md updated** — fixed stale Expo/React Native and Next.js references

### iOS: Phase 1 — Empty & Error States

- New `CalendarPermissionView.swift` — shown when calendar access is denied/not-determined
- New `NetworkMonitor.swift` — NWPathMonitor wrapper with offline banner in MainTabView
- `AIChatView` — added AI unreachable error state with retry button
- `HomeView` — composite "Get Started" card when all sections empty

### iOS: Phase 2 — Settings Screen Completion

- **Delete account** — double confirmation (dialog → type "DELETE" alert), backend call + local wipe
- **Disconnect Gmail** — confirmation dialog, calls `connections.delete` tRPC
- **AI tone picker** — Professional/Casual/Concise preference injected into system prompt
- **Notification toggles** — in-app Task Due Reminders + Calendar Reminders toggles
- New API methods: `TodosAPIClient.deleteAccount()`, `TodosAPIClient.disconnectEmail()`

### iOS: Phase 3 — AI Context Awareness

- `AIChatView` suggestions now tab-aware (Home/Tasks/Email/Calendar each show relevant prompts)
- `AppServices.currentTab` tracks active tab, synced by MainTabView
- AI tone preference synced to `AIChatService.toneInstruction` and injected into system prompt

### iOS: Phase 4 — Session Handling

- `TodosAPIClient` now attempts silent refresh on 401 before marking session expired
- `AuthService.isSessionExpired` flag + `attemptSilentRefresh()` method
- Orange "Session expired — Sign in again" banner in MainTabView

### iOS: Phase 5 — Local Notifications

- New `NotificationService.swift` — UNUserNotificationCenter wrapper with TASK_REMINDER category
- Action buttons: Complete (marks task done) and Snooze 1h (reschedules)
- `TaskCaptureService` schedules/cancels notifications on task create/update/complete/delete
- `TodosApp.swift` — AppDelegate adapter for notification action handling

### iOS: Phase 6 — Database Schema Changes

- Added `emailThreadId` and `eventId` columns to task table in `schema.ts`
- Added indexes: `task_email_thread_id_idx`, `task_event_id_idx`
- Updated `TaskRecord.swift` with new optional properties
- Updated tRPC routes (create, update, sync) to accept and persist both fields

### Files Changed

- `PRD.md`, `AGENTS.md`, `CLAUDE.md`, `APPS_ARCHITECTURE.md`
- `apps/ios/Todus/Todus/App/AppServices.swift`
- `apps/ios/Todus/Todus/App/TodosApp.swift`
- `apps/ios/Todus/Todus/Data/Models/TaskRecord.swift`
- `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`
- `apps/ios/Todus/Todus/Features/Calendar/CalendarPermissionView.swift` (new)
- `apps/ios/Todus/Todus/Features/Home/HomeView.swift`
- `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
- `apps/ios/Todus/Todus/Services/AI/AIChatService.swift`
- `apps/ios/Todus/Todus/Services/API/TodosAPIClient.swift`
- `apps/ios/Todus/Todus/Services/Auth/AuthService.swift`
- `apps/ios/Todus/Todus/Services/NetworkMonitor.swift` (new, from prior session)
- `apps/ios/Todus/Todus/Services/Notifications/NotificationService.swift` (new)
- `apps/ios/Todus/Todus/Services/Tasks/TaskCaptureService.swift`
- `apps/server/src/db/schema.ts`
- `apps/server/src/trpc/routes/tasks.ts`

---

## [2026-03-27] Review follow-up — OTP fallback, compose draft carry-over, and iOS sync/status fixes

### Fixed

- **OTP fallback is now dev-only**: The server no longer retries all failed OTP sends through `resend.dev`. Fallback is restricted to the owner mailbox in non-production environments so normal users are not routed into an impossible delivery path.
- **CreateSheet email drafts now preserve typed text**: Choosing the Email route from the universal create modal now carries the entered text into `EmailComposeView(body:)` instead of discarding it.
- **Reminders sync direction now affects behavior**: The selected direction now governs both initial bootstrap sync/import and live task mutations, so `From Reminders` no longer pushes app changes back out and `To Reminders` no longer imports reminders into Todus.
- **Calendar connection state now recognizes full access**: Settings correctly treats EventKit `fullAccess` as connected, matching the event creation flow on newer iOS versions.
- **Gmail connect screen now refreshes connection state**: After the Gmail consent flow completes, the email tab re-checks the backend connection and loads threads immediately when access is available.
- **Sensitive auth logs were removed from release paths**: Apple auth response logging and Google callback logging in iOS now avoid writing cookies or callback tokens into device logs.
- **Todus simulator build blockers were resolved**: The Xcode target now includes `NetworkMonitor.swift` and `CalendarPermissionView.swift`, and the tracked `CustomTabBar.swift` has been brought back in sync with the implementation expected by `MainTabView`.

### Files

- `apps/server/src/lib/auth.ts`
- `apps/ios/Todus/Todus/App/AppServices.swift`
- `apps/ios/Todus/Todus/Services/Reminders/RemindersSyncState.swift`
- `apps/ios/Todus/Todus/Services/Tasks/TaskCaptureService.swift`
- `apps/ios/Todus/Todus/Navigation/CreateSheet.swift`
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
- `apps/ios/Todus/Todus/Features/Home/HomeView.swift`
- `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailConnectView.swift`
- `apps/ios/Todus/TASK.md`

## [2026-03-27] iOS Create Flow — custom modal overlay + adaptive inputs by type/tab

### Changed

- **`+` action now opens a modal overlay (not system sheet)**: Replaced the old `sheet`-based create UI with an in-app modal overlay that matches the compact floating style.
- **Adaptive create form by selected type**:
  - **Auto**: smart routing (date text -> event, email intent -> email, otherwise task)
  - **Task**: title input + folder selector + due-date picker
  - **Event**: title input + event date/time picker
  - **Email**: title/input mode that opens email compose flow
- **Context-aware defaults by active tab**:
  - **Calendar tab** -> defaults to Event
  - **Tasks tab** -> defaults to Task
  - **Home tab** -> defaults to Auto
  - **Email tab** -> defaults to Email
- **Folder selector default**: Defaults to `Inbox` (no folder) as requested.

### Files

- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
- `apps/ios/Todus/Todus/Navigation/CreateSheet.swift`

## [2026-03-27] iOS Tab Screens — unified top header across all tabs

### Changed

- **Shared top header**: Added a reusable `AppTopHeader` for tab root screens with:
  - user avatar on the top-left (profile image or initials fallback),
  - large page title below,
  - dual-action pill on the top-right.
- **Dual actions**: Added two utility actions in the right pill:
  - notifications button (opens iOS notification settings),
  - more/settings button (opens app Settings sheet).
- **Applied on all tab roots**:
  - Home
  - Tasks
  - Inbox
  - Calendar

### Files

- `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift`
- `apps/ios/Todus/Todus/Features/Home/HomeView.swift`
- `apps/ios/Todus/Todus/Features/Tasks/TasksTabView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`

## [2026-03-27] iOS Calendar — create events on tap (no long-press required)

### Fixed

- **Tap-to-create on timeline**: Tapping an empty time slot in the calendar now immediately starts creating a new event.
- **Long-press still supported**: Existing long-press creation behavior remains available.

### Files

- `apps/ios/Todus/Todus/Features/Calendar/CalendarViewController.swift`

## [2026-03-27] iOS Onboarding — visual restyle + real provider logos

### Changed

- **Onboarding visual refresh**: Restyled onboarding layouts to match the app's current spacing, typography, and button rhythm used elsewhere in iOS.
- **Real provider logos**: Replaced generic SF Symbol icons with the same branded provider icons used in Settings:
  - Gmail onboarding now uses `GmailIconView`
  - Reminders onboarding now uses `AppleRemindersIconView`
- **Primary CTA alignment**: Added small provider logos inside the primary connect buttons for stronger visual consistency and recognizability.

### Files

- `apps/ios/Todus/Todus/App/GmailOnboardingView.swift`
- `apps/ios/Todus/Todus/Features/Settings/RemindersSetupView.swift`

## [2026-03-27] iOS Auth, AI Sheet, and Inbox Avatars — autofill + interactive half sheet + robust fallbacks

### Auth

- **Email OTP autofill improvements**: Login email field now uses iOS email autofill hints (`textContentType(.emailAddress)`) and supports submit from keyboard. OTP field keeps native one-time-code autofill and uses a done submit label.

### AI Chat Sheet

- **Half-page AI sheet**: AI chat now opens with a 50% height detent and can expand to full screen.
- **Background remains interactive at half detent**: Enabled background interaction up to the half detent so underlying page context remains visible and scrollable while the AI sheet is half-open.

### Inbox Avatars

- **No more blank avatar slots**: Sender avatar view now always renders initials with a colored circle as a guaranteed base layer.
- **More resilient fallbacks**: Added local domain fallback URL waterfall (`/favicon.ico`, `apple-touch-icon`, DuckDuckGo icon API, Google S2 favicon) when backend avatar resolution is slow/fails.
- **Subdomain and edge-case handling**: Added normalization + root-domain extraction with common multi-part TLD support (`co.uk`, `com.au`, etc.) and `www.` host variants.
- **Cache normalization**: Avatar cache now keys by normalized lowercase email to avoid misses from casing/whitespace differences.

### Files

- `apps/ios/Todus/Todus/Features/Auth/AuthView.swift`
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
- `apps/ios/Todus/Todus/Features/Email/SenderAvatarView.swift`

## [2026-03-27] iOS — Custom glass tab bar (two-pill layout)

### Changed

- **Replaced system TabView** with a fully custom tab bar using `safeAreaInset(edge: .bottom)` — eliminates `tabViewBottomAccessory` full-width stretching issues entirely.
- **Two-pill layout**: left pill (4 nav tabs, fills width) + right pill (AI + Create, fixed size). Active tab shows filled icon + subtle blue rounded-rect indicator.
- **Glass material**: iOS 26 uses `.glassEffect(in: Capsule())` (Liquid Glass); iOS 17/18 uses `.ultraThinMaterial` capsule + drop shadow.
- **AI icon**: `lasso.badge.sparkles` with `.symbolRenderingMode(.multicolor)` for colorful rendering.
- **Create button**: "+" inside a small `Color.primary` filled circle (inverts in dark mode).
- **Content inset**: `safeAreaInset` pushes all content up automatically — no manual padding needed per-view.

### Files

- `apps/ios/Todus/Todus/Navigation/CustomTabBar.swift` ← new
- `apps/ios/Todus/Todus/Navigation/MainTabView.swift` — stripped to content+safeAreaInset only

## [2026-03-27] iOS Settings — Native logout confirmation modal

### Changed

- **Logout confirmation**: Added native iOS confirmation dialog before signing out from the Settings account section. Tapping "Log out" now first shows a destructive confirm step with cancel option.

### Files

- `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift`

## [2026-03-27] iOS Settings overhaul — Google avatar, functional toggles, sync direction, brand icon fix

### Account Section

- **Google avatar + name**: Account card now shows AsyncImage from Google profile URL, display name, and email. Falls back to letter-initial circle if no image. `fetchUserProfile()` called on auth completion and when settings opens.
- **Logout moved into account card**: Removed standalone logout section; logout button now lives inside the Account section card.
- **Removed "Signed in" badge**: Email address shown below name instead.

### Email Section (functional toggles)

- **Swipe Gestures**: Toggle now bound to `services.swipeGesturesEnabled` (was static).
- **Email Signature**: Toggle bound to `services.signatureEnabled`; inline text field appears when enabled, bound to `services.signatureText`.
- **Thread Grouping**: Toggle bound to `services.threadGroupingEnabled` (was `.constant(true)`).

### Reminders Sync Direction

- **`RemindersSyncDirection` enum** added to `SyncModels.swift`: `.twoWay`, `.toReminders`, `.fromReminders` with titles, subtitles, icons.
- **RemindersSetupView**: Added inline picker for sync direction (shown when sync is enabled).

### Icons on all settings items

- Added `Label(_, systemImage:)` to AI, Preferences, About, Privacy sections.

### Brand Icon Fix

- Added `.aspectRatio(1, contentMode: .fit)` to `GmailIconView`, `AppleCalendarIconView`, `AppleRemindersIconView` to prevent stretching.

### Files

- `apps/ios/Todus/Todus/Features/Settings/SettingsView.swift` — Full rewrite
- `apps/ios/Todus/Todus/Features/Settings/RemindersSetupView.swift` — Sync direction picker
- `apps/ios/Todus/Todus/Domain/SyncModels.swift` — RemindersSyncDirection enum
- `apps/ios/Todus/Todus/DesignSystem/BrandIcons.swift` — 1:1 aspect ratio fix
- `apps/ios/Todus/Todus/Services/Auth/AuthService.swift` — fetchUserProfile on auth completion

## [2026-03-27] iOS Email — Clean minimal redesign, glass buttons, star + mark-unread

### Thread View

- **Header redesign**: Glass icon buttons (34×34) for back, star, mark-as-unread, archive, trash. Subject + sender name shown inline. Star derived from thread labels; toggles optimistically.
- **Mark as unread**: Taps `markAsUnread` + dismisses to inbox so the row shows unread immediately.
- **Cleaner message bubbles**: Sender row is a tap target for collapse; body has an inset section with hairline divider. Softer `rowStroke` border.
- **Header material**: `.ultraThinMaterial` with divider overlay.

### Inbox

- **Row separators**: `listRowSeparator(.visible)` with `AppTheme.divider` tint.
- **Loading indicator**: Inline spinner next to "Inbox" title during refresh.
- **Glass search bar**: `.glassEffect(in:)` on iOS 26; surface card fallback.
- **Unread accent bar**: 3pt vertical bar on left edge instead of floating dot.
- **Settings button**: Now uses `LiquidGlassButtonStyle`.

### Files

- `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailRowView.swift`

## [2026-03-27] iOS Settings — Full overhaul with brand icons, better appearance, more options

### Bug Fix

- **Settings buttons now work**: `hasSeenOnboarding` on `AuthService` changed from a computed UserDefaults property to a stored `@Observable` var. SwiftUI now detects the change and `RootView` correctly switches to `AuthView` when the user logs out or taps "Sign in". Previously, no observable change occurred when `authState` was already `.guest`. (`AuthService.swift`)
- **Cards visible in light mode**: `AppTheme.backgroundBottom/Top` changed from `0.99` to `0.94` in light mode, matching iOS `systemGroupedBackground`. List cells (white) now contrast clearly against the gray background. Dark mode surface raised slightly `0.09 → 0.11` to reduce harsh contrast. (`AppTheme.swift`)

### Feature: Brand Icons

- **`BrandIcons.swift`** (new): `GmailLogo` — pixel-accurate SVG-path recreation using `Canvas` + five filled paths (blue/green/yellow/red/dark-red). `AppleCalendarLogo` — red header + large day number. `AppleRemindersLogo` — three coloured dot rows. All wrapped in `AppIconContainer` with iOS-style rounded-rect background and shadow. (`BrandIcons.swift`)

### Feature: Improved Settings UI

- **Appearance selector**: Replaced `.segmented` picker with three visual preview cards (mini mock-UI swatch + icon + label). Selection shows blue border + checkmark. (`SettingsView.swift`)
- **Account section**: Avatar circle with email initial, green/orange status dot, cleaner layout.
- **Connected Services**: Proper brand icons with connection status. Apple Calendar shows "Connect" button when not authorized.
- **New sections**: Email (thread grouping, unsubscribe, signature, swipe actions), AI Assistant (task read/write toggles), Privacy (app permissions, data sync info).
- **AI model picker**: Developer section `Model` row is now a `Picker` showing all `preferredModels`, directly bound to `aiChatService.selectedModel` via `@Bindable`.
- **Log out button**: Always says "Log out" (was conditionally "Return to Login"). (`SettingsView.swift`)

## [2026-03-27] iOS Thread View — Auto-height body, swipe back, liquid glass, AI summary

### Bug Fix

- **Email body no longer clipped**: Replaced fixed `maxHeight: 600` frame with dynamic WKWebView height measurement (`document.documentElement.scrollHeight` via `evaluateJavaScript`). Two-pass measurement (immediate + 700ms delay) handles late-loading images. Emails now expand to full content height.
- **`markAsRead` reliability**: Replaced `async let _ = markAsRead` with a named `async let` plus explicit `await` so the read request is not dropped (Swift structured-concurrency pitfall, see Swift #62027).
- **WKWebView flicker**: `EmailHTMLView.updateUIView` only calls `loadHTMLString` when raw `html` changes, not when height measurement updates state — avoids redundant reloads per message.

### Feature: Swipe-to-go-back

- **`SwipeBackEnabler`** (new in `AppTheme.swift`): `UIViewControllerRepresentable` that re-enables `interactivePopGestureRecognizer` after `.navigationBarBackButtonHidden(true)`. Applied to `EmailThreadView`.

### Feature: Liquid Glass Reply Button

- **`LiquidGlassButtonStyle`** (new in `AppTheme.swift`): Uses `.glassEffect(in:)` on iOS 26+, falls back to surface+border card on older iOS. Reply bar uses this style.

### Feature: AI Summary Card

- **`AISummaryCard`**: Collapsible summary at the top of the thread. Calls `brain.generateSummary` tRPC endpoint (uses `@cf/facebook/bart-large-cnn` — Cloudflare Workers AI, free tier). Only shown when the brain has vectorized the thread. Styled with a purple accent border matching the web app.

### Refactor

- `MessageBubble` now uses `SenderAvatarView` (size: 32) instead of its own initials/color logic.
- `EmailHTMLView` extracted into `ExpandingEmailHTMLView` wrapper — cleaner height state management.

### Files

- `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift`
- `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift`
- `apps/ios/Todus/Todus/Features/Email/SenderAvatarView.swift` (added `size` param)

## [2026-03-27] iOS Inbox — Real Sender Avatars with Fallback Chain

### Feature

- **`SenderAvatarView`**: New SwiftUI component that resolves real sender avatars via the existing backend `avatar.getByEmail` tRPC endpoint (Google People API → domain favicon → fallbacks → initials).
- **`AvatarCache`**: `@Observable` singleton that deduplicates in-flight requests and caches results for the session. Views re-render automatically when a cache entry arrives.
- **Waterfall fallback**: `AsyncImage` tries URLs in priority order; advances to next on load failure, ending at initials + deterministic color circle if all fail.
- **Subdomain handling**: Handled by the backend — `auth.supabase.com` resolves to the Supabase root-domain logo.

### Files

- `apps/ios/Todus/Todus/Features/Email/SenderAvatarView.swift` (**new** — add to Xcode project)
- `apps/ios/Todus/Todus/Features/Email/EmailRowView.swift` — replaced inline initials avatar with `SenderAvatarView`

## [2026-03-27] iOS Tab Bar — HIG-Compliant Layout, Calendar Fix, Floating Action Pill

### Structural Fix

- **Separated tabs from actions**: Removed `tabViewBottomAccessory` and `safeAreaInset` accessory patterns. Both caused the action buttons to stretch full-width and merge visually with the tab bar, violating Apple HIG (tabs = navigation, actions ≠ tabs).
- **Floating action pill**: AI and Create buttons now live in a compact vertical pill (~44×88pt, glass material) that floats bottom-right above the tab bar — clearly a separate control, not a tab.

### Calendar Clipping Fix

- **Removed double NavigationStack**: `CalendarContainerView` creates its own `UINavigationController` internally. Wrapping it in another `NavigationStack` from `tabContent(for:)` broke safe-area propagation, causing the bottom ~30% of calendar content to be clipped behind the tab bar.

### Tint Color Fix

- **`AppTheme.accentBlue`**: Changed from `Color(red: 0.25, green: 0.48, blue: 1.0)` (purple-shifted) to `Color.blue` (system iOS blue, matches `AppPrimaryButtonStyle`).

### Files Updated

- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
- `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift`

## [2026-03-26] UX Fixes — Usability, Touch Support & Discoverability

### Critical Fixes

- **Security settings**: Replaced non-functional 2FA toggle and Delete Account button with clear "Coming soon" state. Prevents users from thinking they've enabled security features that don't exist yet. (`settings/security/page.tsx`)
- **Thread action toolbar touch support**: Action buttons (star, archive, delete) now visible when a thread is selected/focused, not just on hover. Touch devices (tablets, phones) can now access these core actions. Added `@media (pointer: coarse)` CSS rule for broader touch support. (`mail-list.tsx`, `globals.css`)

### High-Impact Improvements

- **CC/BCC toggle visibility**: Replaced invisible plain-text Cc/Bcc buttons with styled toggle buttons that show active state (blue highlight when enabled). Much more discoverable in compose view. (`email-composer.tsx`)
- **Keyboard shortcuts overlay**: New `?` key shortcut opens a grouped, scrollable dialog showing all keyboard shortcuts organized by scope (Navigation, Global, Mail List, Thread, Compose). Replaces the old behavior of navigating away to settings. (`keyboard-shortcuts-dialog.tsx`, `hotkey-provider-wrapper.tsx`)
- **Context-sensitive empty states**: Mail list empty state now shows "No results found" with "clear filters" action when searching, vs. "No emails in this folder yet" when the folder is genuinely empty. (`mail-list.tsx`)

### Medium Fixes

- **iOS swipe-to-go-back**: Restored native swipe-back gesture in `EmailThreadView` by using `.navigationBarBackButtonHidden(true)` instead of `.toolbar(.hidden)`. Custom back button still renders, but iOS swipe gesture now works. (`EmailThreadView.swift`)

### Verified Working (no changes needed)

- **Undo toasts**: Archive/delete already have undo toasts with delayed execution — confirmed working via `createPendingAction` in `use-optimistic-actions.ts`.
- **Connections page**: Legitimate user-facing feature (manage connected email accounts), not debug info.
- **Category selection**: Uses dropdown with checkmarks — clear selected state already present.

## [2026-03-26] iOS Performance — Fix Hangs & UI Freezes

### Computed Property Caching (HIGH impact)

- **CalendarTaskView**: `buckets` computed property now cached in `@State`, recomputed only on `allTasks`/`searchText`/`selectedFolderID` changes instead of every body evaluation.
- **HomeView**: `tasksDueToday` cached in `@State`, recomputed on `allTasks` change.
- **EmailInboxView**: `filteredThreads` cached in `@State`, recomputed on `searchText`/`threads` change.
- **TaskTableView**: `visibleTasks` cached in `@State`, recomputed on `allTasks`/`selectedFolderID` change.
- **BoardView**: `filteredTasks(for:)` (called 4x per render) replaced with pre-grouped `@State` dictionary computed once.

### Startup Parallelization

- **RootView**: Auth upgrade and reminders setup now run concurrently via separate `.task` modifiers instead of sequentially.

### Settings Sheet Binding

- **MainTabView**: Replaced inline `Binding(get:set:)` with proper `@Bindable` pattern for `showsSettings`.

### Email Service Optimization

- **EmailService**: Batched parallel thread fetches into groups of 8 (was 30 simultaneous requests).

### Bug Fixes

- **EmailModels**: Fixed `EmailMessage` and `EmailAttachment` `Codable` → `Decodable` (they're only decoded from API responses, custom `CodingKeys` prevented `Encodable` synthesis).
- **EmailThread**: Added `Equatable` conformance for `.onChange(of:)` support.

## [2026-03-26] UI Polish — Refined Design Tokens, Typography & Visual Consistency

### Design Token Refinements (globals.css)

- **Softened foreground colors**: Light mode foreground moved from near-pure-black `hsl(240 10% 3.9%)` to softer `hsl(240 6% 13%)`. Dark mode foreground eased to `hsl(0 0% 93%)`.
- **Warmed backgrounds**: Light bg shifted to `hsl(0 0% 99%)`, dark bg to `hsl(240 4% 7.5%)`. Static hex colors use slightly warm grays instead of pure blacks.
- **Tightened typography**: Base letter-spacing set to `-0.011em`, headings to `-0.02em`. Body line-height `1.5`, heading line-height `1.2`. Font smoothing enabled globally.
- **Softer borders/rings**: Border and ring values use slightly more neutral hues with lower saturation.

### Component Updates

- **button.tsx**: Text tightened to `13px`, transitions smoothed to `150ms`.
- **card.tsx**: Rounded from `2xl` to `xl`, shadow softened. Card title from `2xl` to `lg`. Padding tightened from `p-6` to `p-5`.
- **input.tsx**: Height from `h-10` to `h-9`, rounded from `xl` to `lg`, text `13px`.
- **settings-card.tsx**: Removed hardcoded `panelLight/panelDark` for `transparent`. Tighter spacing.

### Sidebar Refinements

- **Removed purple upgrade button** (`#8B5CF6` → `mainBlue`). Tighter spacing and smaller text.
- **Compose button**: Uses `mainBlue` token. Smoother transition.
- **Sidebar padding**: Reduced from `px-4` to `px-3` for tighter layout.
- **Nav section titles**: Changed from `13px` to `11px uppercase tracking-wide` for clear visual hierarchy.
- **Hover states**: Replaced hardcoded `bg-subtleWhite`/`dark:bg-[#202020]` with `bg-accent` token.

### Navigation & User Area

- **Replaced 20+ hardcoded hex colors** (`dark:bg-[#131313]`, `dark:bg-[#141414]`, `text-black dark:text-white`, etc.) with semantic tokens (`bg-popover`, `bg-card`, `text-foreground`, `bg-background`).
- **Tighter user info section**: Reduced spacing between name, email, and verification badge.

### Login Page

- **Tighter layout**: Narrowed max-width to `340px`, reduced padding and heading sizes.
- **Typography**: Headings from `2xl` to `xl`, links from `text-xs` to `11px`.
- **Showcase panel**: Rounded from `2.5rem` to `2xl`, softened border/shadow.

### Mail List (thread items)

- **Hover**: Replaced `bg-offsetLight`/`dark:bg-primary/5` with `bg-accent/60` + `transition-colors`.
- **Action bar**: Tightened from `rounded-xl p-1 gap-1` to `rounded-lg p-0.5 gap-0.5` with softer shadow.
- **Unread dot**: Smaller (`1.5` from `2`), uses `mainBlue` token.
- **Date text**: Reduced to `11px`.
- **Content preview**: Tighter margins, `12px` text.
- **Removed all hardcoded tooltip backgrounds** (`bg-white dark:bg-[#1A1A1A]`).

### Thread Display

- **Container**: Replaced `bg-panelLight dark:bg-panelDark` with `bg-card`.
- **All action buttons**: Replaced `bg-white dark:bg-[#313131]`/`hover:bg-gray-100 dark:hover:bg-[#404040]` with `bg-card hover:bg-accent`.
- **Reply button**: Cleaner token-based styling.
- **Empty state**: Tighter text sizes, token-based colors.

### Settings Layout

- **Replaced all hardcoded border/bg colors** with `border-border/60` and `bg-card`.
- **Slightly tighter padding** and reduced shadow.

### iOS Refinements

- **AppTheme.swift**: Slightly adjusted dark mode background from `0.04` to `0.05` white, surface values nudged 1% lighter. Border opacities reduced for subtlety. Shadow reduced from `0.08` to `0.06`.
- **EmailInboxView**: Inbox header font `28→24` with tighter tracking. Search bar corners `16→12`, thinner border.
- **EmailThreadView**: Subject font `17→16` with tracking. Reply bar height `44→42`, corners `14→12`.

### Files Updated

- `apps/mail/app/globals.css`
- `apps/mail/components/ui/button.tsx`
- `apps/mail/components/ui/card.tsx`
- `apps/mail/components/ui/input.tsx`
- `apps/mail/components/ui/app-sidebar.tsx`
- `apps/mail/components/ui/nav-main.tsx`
- `apps/mail/components/ui/nav-user.tsx`
- `apps/mail/components/ui/settings-content.tsx`
- `apps/mail/components/settings/settings-card.tsx`
- `apps/mail/components/mail/mail-list.tsx`
- `apps/mail/components/mail/thread-display.tsx`
- `apps/mail/components/mail/mail.tsx`
- `apps/mail/app/(auth)/todus/login/page.tsx`
- `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift`

## [2026-03-26] iOS — Replace Custom Tab Bar with System Liquid Glass TabView

### Changed

- **MainTabView**: Replaced the hand-made HStack tab bar with iOS 26's system `TabView` using the new `Tab("Title", systemImage:, value:)` API. The system now renders the Liquid Glass floating bar automatically.
- **Tab selection persistence**: Switched from `@State` to `@SceneStorage("selectedTab")` so the last-used tab is restored across scene sessions.
- **Minimize on scroll**: Added `.tabBarMinimizeBehavior(.onScrollDown)` so the bar shrinks to a pill when scrolling content.
- **Bottom accessory**: Moved the "+" create and AI sparkles buttons into `.tabViewBottomAccessory` — they now float correctly above the glass bar.
- **Accent colors**: Added `AppTheme.accentBlue` (rgb 0.25/0.48/1.0) and `AppTheme.mutedGray` to the design system. Active tab uses accent blue via `.tint()`.
- **AppTab.title**: Added a `title` computed property for human-readable tab labels.
- **Removed padding hacks**: Removed 60–90pt bottom padding workarounds in TasksTabView, EmailInboxView, and EmailThreadView that compensated for the old custom bar.

### Files Updated

- `apps/ios/Todus/Todus/Navigation/MainTabView.swift`
- `apps/ios/Todus/Todus/Navigation/AppTab.swift`
- `apps/ios/Todus/Todus/DesignSystem/AppTheme.swift`
- `apps/ios/Todus/Todus/Features/Tasks/TasksTabView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailInboxView.swift`
- `apps/ios/Todus/Todus/Features/Email/EmailThreadView.swift`

## [2026-03-26] Deploy Command Parsing Clarification (Docs)

### Fixed

- **Deploy Usage**: Clarified that inline `# ...` text after `pnpm run` commands may be forwarded as real CLI args to Wrangler (triggering `Unknown arguments`), and showed the correct deploy commands (`pnpm run deploy:backend` / `pnpm run deploy:frontend`). (docs/terminal-commands.md)
- **Env Selection**: Updated deployment docs to run Wrangler via `pnpm --filter=... exec wrangler` and explicitly pass `-e staging` / `-e production` (avoids relying on pnpm script argument passthrough and fixes “wrangler: command not found”). (docs/terminal-commands.md)

## [2026-03-11] Sender Avatar Resolution Upgrade

### Changed

- **Sender Avatars**: Replaced the previous inbox sender-avatar fallback chain of `BIMI -> external image API -> initials` with a server-backed resolver that now prefers `Google People contact photos -> BIMI -> sender domain favicon`.
- **Cross-Platform Consistency**: Updated both the web mail client and the native iOS inbox/thread sender avatars to use the same server response and favicon fallback list.

### Notes

- **Google Reconnect Requirement**: Existing Google connections may need to reconnect before contact-photo lookups work, because the new resolver requires Google Contacts read scopes in addition to the existing Gmail scopes.

## [2026-03-08] AI Chat Billing Gate UX Fix

### Fixed

- **AI Chat Placeholder**: Restored visible placeholder text in the web AI chat composer by adding explicit Tiptap placeholder rendering styles.
- **Billing Gate Submit Guard**: Prevented `Enter` from submitting AI chat requests when `chat-messages` billing is disabled, so free/blocked states now open the pricing dialog instead of throwing a generic `useChat` error.

## [2026-03-08] Composer AI GPT-5 Compatibility

### Fixed

- **Email Composer AI**: Updated the server-side composer and subject-generation OpenAI calls to use GPT-5-compatible completion token options, fixing 500 errors when generating subjects or drafting content from the email composer.

## [2026-03-05] Login Refinement & Email Connection Guard

### Added

- **Connection Guard**: Implemented `ConnectionWrapper` for the web app, forcing users with 0 email connections (e.g., Apple Sign-in or Email/Password) to link a provider before accessing the mail UI.
- **Backend Graceful Failure**: Updated `activeConnectionProcedure` to throw `NOT_FOUND` instead of signing the user out when no connection exists.

### Fixed

- **Login Screen (iOS)**:
  - **Apple Auth Cancellation**: Gracefully handle `ERR_REQUEST_CANCELED` and similar codes to prevent error popups when users cancel authentication.
  - **Isolated Loading States**: Split Google and Apple loading states so activity spinners only show on the pressed button.
  - **Button Spacing**: Reduced gap between Google and Apple buttons to exactly 16px (1rem).
  - **Logo Balance**: Resized the top-left logo from 32px to 24px for a more balanced aesthetic with the "Todus" wordmark.

## [2026-03-02] Login UI & Logo Visibility

### Fixed

- Fixed logo visibility on iOS login screen by implementing adaptive `tintColor` (black for light mode, white for dark mode).
- Removed native iOS navigation header from login screen to match web app aesthetic.

### Changed

- Updated iOS login screen to better align with web app layout and typography.

## [2026-03-01] App Consolidation + Archive Cleanup

### Changed

- Consolidated active app surface to:
  - `apps/ios` (only active iPhone native app)
  - `apps/macos` (only active desktop webview wrapper)
- Archived duplicate/legacy app implementations to `apps/archived/*`:
  - `apps/native` -> `apps/archived/native`
  - `apps/webview-swift` -> `apps/archived/webview-swift`
  - `apps/apple` -> `apps/archived/apple`
- Removed `native:*` scripts from root `package.json` to prevent accidental double-build paths.

### Updated

- Updated app structure and scripts documentation to reflect the canonical targets.
- Renamed remaining archived native Xcode display/product naming from `Zero*` to `Todus` (display/product/module identifiers in archived native projects).

## [2026-03-01] EAS Build Configuration

### Added

- **EAS Project ID**: Added `extra.eas.projectId` to `apps/ios/app.config.ts` for EAS builds
- **App Version Source**: Set `cli.appVersionSource` to `"local"` in `apps/ios/eas.json` to use app.config.ts version

### Files Modified

- `apps/ios/app.config.ts` - Added EAS project ID (10b2cbe2-6786-4328-a831-ba6ccbca1e89)
- `apps/ios/eas.json` - Added appVersionSource configuration

## [2026-03-01] App Structure Reorganization

### Changed

- **apps/apple → apps/webview-swift**: Moved SwiftUI WebView wrapper to clearly indicate it's a legacy wrapper, not the primary native app (`apps/apple/` → `apps/webview-swift/`).
- **apps/native deprecation**: Marked `apps/native` as deprecated in favor of `apps/ios` which is more complete and TestFlight-ready. Added `DEPRECATED.md` to guide developers to the correct app.

### Added

- **APPS_STRUCTURE.md**: Comprehensive documentation of all apps in the monorepo with status, purpose, and recommended usage.
- **APPS_NATIVE_MIGRATION.md**: Migration plan for deprecating `apps/native` in favor of `apps/ios`.
- **SCRIPTS_GUIDE.md**: Quick reference guide for all package.json scripts with explanations and recommended workflows.

### Architecture Decision

**Primary Apps Going Forward**:

- **Web**: `apps/mail` (Next.js)
- **iOS**: `apps/ios` (Expo React Native) - TestFlight ready
- **macOS**: `apps/macos` (Electron wrapper)
- **Backend**: `apps/server` (Cloudflare Worker)

**Deprecated/Legacy**:

- `apps/native` - Less complete than apps/ios, only kept for potential macOS React Native development
- `apps/webview-swift` - Simple WebView wrapper, not a true native app

## [2026-03-08] Local Mail Auto-Sync Fallback

### Fixed

- **Local Inbox Freshness**: Added a local-only auto-sync fallback that periodically triggers the existing `mail.forceSync` path and refreshes the inbox data, so new emails appear during local development without relying on Gmail push webhooks.
- **Production Safety**: Kept this behavior gated to Vite dev sessions pointed at a localhost backend, leaving staging and production mail sync behavior unchanged.

## [2026-03-08] Local tRPC Rate Limit Fallback

### Fixed

- **Local Settings/Labels 500s**: Resolved `settings.get` and `labels.list` failing with `Invalid token` when the local Redis/Upstash token is expired or mismatched.
- **tRPC Redis Resilience**: Updated `apps/server/src/trpc/trpc.ts` so rate-limited procedures keep working in `local` and `development` when Redis is unavailable, while still enforcing rate limits normally when Redis is healthy.

## [2026-03-01] Login Page Styling

### Changed

- **Auth Layout**: Redesigned the `login` and `signup` pages to a 2-column layout. The left column now hosts the authentication form with a top-left logo placement, while the right column displays a beautifully padded, high-radius hero image (`email-preview.png`) (`apps/mail/app/(auth)/todus/login/page.tsx`, `apps/mail/app/(auth)/todus/signup/page.tsx`).
- **Typography & Details**: Adjusted typography to match requests—"Your AI agent for emails" is now at parity with header size but muted, and sub-text changed to "Sign up for free with your email".

## [2026-03-01] Google OAuth 500 Fix & Redis Robustness

### Fixed

- **OAuth Callback**: Resolved a 500 Internal Server Error during Google OAuth login caused by an invalid `REDIS_TOKEN`.
- **Redis Resilience**: Implemented a `try/catch` fallback mechanism in `apps/server/src/lib/auth.ts` to gracefully switch to PostgreSQL session storage if Redis connection fails (e.g., due to expired/invalid tokens).
- **Cleanup**: Removed temporary debug instrumentation from `main.ts`.
- **Onboarding Assets**: Fixed broken image/animation links in the onboarding modal by switching from non-resolving `assets.todus.app` to local `/public/onboarding` assets.

## [2026-02-27] Frontend Stability & Environment Config Fixes

### Fixed

- **App Crashes**: Resolved `TypeError: Cannot read properties of undefined (reading 'id')` by adding protective optional chaining for `session?.user?.id` inside various frontend hooks and components.
- **Environment Variables**: Fixed `VITE_PUBLIC_BACKEND_URL` resolving to `undefined` on Cloudflare Pages (which broke Sentry and Autumn API calls) by refactoring `vite.config.ts` to properly inject explicit `process.env` definitions via `loadEnv`.
- **API Auth Errors**: Fixed `401 Unauthorized` errors on `/api/autumn/customers` cross-origin calls by passing `includeCredentials={true}` to `AutumnProvider` to ensure session cookies are sent to the backend.

## [2026-02-27] tRPC Errors & UI Polishing

### Fixed

- **tRPC API**: Resolved 500 Internal Server Error in `brain.generateSummary` caused by missing Vectorize indexes (`VECTOR_GET_ERROR`) by implementing a try-catch fallback.
- **UI Warnings**: Fixed `react-resizable-panels` console warnings by strictly defining `id` and `order` properties for all `ResizablePanel` components, and restoring missing `<ResizableHandle />` elements.

## [2026-02-27] Todus Branding & SEO Finalization

### Fixed

- **Rebranding Errors**: Fixed TypeScript lint errors resulting from incomplete rename operations in `auth.ts`, `email-sequences.tsx`, and `sanitize-tip-tap-html.ts`.

### Changed

- **Global Branding**: Renamed "Zero" to "Todus" across configuration, internationalization files (\*.json), static pages, and the footer.
- **Brand Assets**: Updated logo asset URLs, onboarding vide links, and the GitHub repository link to point to Todus domains.
- **Code Settings**: Refactored the signature field from `zeroSignature` to `todusSignature` on both the frontend and the database schema.
- **SEO Elements**: Updated title tags, meta descriptions, and application headers to index correctly for "Todus".

## [2026-02-27] Login UI Polishing & Web Alignment

### Added

- **Colored Google Logo**: Added `GoogleColored` (iOS) and `GoogleColor` (Web) SVG components for better brand recognition.
- **Brand Identity**: Integrated `brand-logo.png` into both iOS and Web login screens.

### Changed

- **UI Copy**: Standardized welcome messaging to "Welcome to Todus" and "Your AI agent for emails".
- **Styling**: Implemented pill-shaped (fully rounded) buttons and inputs for a more modern and premium aesthetic.
- **Theme Support**: Verified full light/dark mode support for the iOS login screen.
- **Compatibility**: Switched iOS from `expo-image` to standard `react-native` `Image` to resolve native module resolution issues.

## [2026-02-25] iOS App: WebView → Native React Native (Expo Router)

### Added

- **Full native iOS app** replacing the Cloudflare WebView wrapper with real React Native screens
- **Expo Router** file-based navigation with Gmail-style drawer, stack, and modal patterns
- **Auth**: OAuth login via Google/Microsoft with bearer token stored in iOS Keychain (expo-secure-store)
- **Mail List**: Thread list per folder (Inbox, Sent, Draft, Starred, Snoozed, Archive, Spam, Trash) via TRPC
- **Thread Detail**: Full message rendering with HTML WebView, archive/delete/spam/star actions
- **Compose**: Email composer with reply/forward mode, To/Cc/Subject/Body fields
- **Search**: Debounced search modal with live thread results
- **Settings**: Hub with General, Appearance (theme toggle), Connections, and Labels screens
- **Drawer Sidebar**: Folder navigation + logout with session clearing
- **Offline caching**: AsyncStorage-backed React Query persistence

### Architecture

- `apps/ios/app/` — Expo Router file-based routes (auth, mail, settings, compose, search)
- `apps/ios/src/` — Providers (TRPC, React Query, Jotai), features (mail, auth, compose), shared (theme, state, storage)
- Ported ~80% of code from `apps/native/` (React Navigation) and adapted for Expo Router
- TypeScript strict mode with zero app-level type errors

### Files Created (~40 new files)

- Config: `babel.config.js`, `metro.config.js`, updated `package.json`, `app.config.ts`, `tsconfig.json`
- Shared: `env.ts`, `secure-storage.ts`, `session.ts`, `ThemeContext.tsx`, `icons.tsx`
- Providers: `AppProviders.tsx`, `QueryTrpcProvider.tsx`, `SessionBootstrap.tsx`
- Auth: `native-auth.ts`, `login.tsx`, `web-auth.tsx`
- Mail: `[folder].tsx`, `thread/[threadId].tsx`, `ThreadListItem.tsx`, `MessageCard.tsx`, `MailSidebar.tsx`
- Compose: `compose.tsx`
- Search: `search.tsx`
- Settings: `_layout.tsx`, `index.tsx`, `general.tsx`, `appearance.tsx`, `connections.tsx`, `labels.tsx`

---

## [2026-02-21] iOS/Mac Wrapper and Todus Branding Updates

### Added

- Added `/docs/terminal-commands.md` with end-to-end startup/build/deploy commands
- Added `/docs/share-asap.md` with fastest distribution path for friends (web + TestFlight)

### Changed

- iOS wrapper now keeps HTTP/HTTPS navigation in-app and starts at `/mail/inbox`
- iOS wrapper now uses safe area/inset behavior to reduce clipped content at top/bottom
- Added env-driven app name support:
  - `VITE_PUBLIC_APP_NAME` (web branding)
  - `EXPO_PUBLIC_APP_NAME` (iOS/macOS wrapper title/loading text)
- Updated visible branding on login/onboarding/navigation/footer/manifest from Zero to Todus in key user-facing surfaces

### Notes

- OAuth browser handoff can still happen depending on Google provider behavior; this is not Supabase-specific in this stack

## [2026-02-08] Local Development Complete ✅

### Milestone

- Successfully logged in via Google OAuth
- Viewing and reading emails works
- Ready to deploy to production

---

## [2026-02-08] Initial Local Development Setup

### Added

- Cloned Mail-Zero repository from `staging` branch
- Set up local Docker Postgres, Redis (Valkey), and Upstash Proxy containers
- Configured `.env` and `.dev.vars` with development credentials
- Initialized database schema via `pnpm db:push`

### Fixed

- **Docker**: Changed Valkey image tag from `8.0` to `latest` (fix for image not found)
- **Twilio**: Made Twilio service optional for local development (returns mock when `TWILIO_PHONE_NUMBER` is missing)

### Environment Files Updated

- `/apps/server/.dev.vars` - Synced with root `.env` credentials
- `docker-compose.db.yaml` - Fixed Valkey image tag

### Notes

- Twilio phone number is NOT required for local development (SMS 2FA is mocked)
- Resend API key is NOT required for local development (email sending is mocked)
- Redis uses `upstash-local-token` which matches the Docker proxy setup

[2026-02-21] [Feature] Integrated real TRPC data for the native Thread list (N3-05) via useQuery hook on MailFolderScreen and ThreadListItem (apps/native/src/features/mail/\*).

[2026-03-01] [Fix] Fixed chat modal opacity overlay, restricted pricing dialog trigger area to primary CTA button, and resolved chat connection Error code 400 by adjusting unsupported gpt-5 model name configuration to gpt-4o. (apps/mail/components/ui/ai-sidebar.tsx, apps/mail/components/create/ai-chat.tsx, apps/server/.dev.vars).

[2026-03-09] [Fix] Added native sender avatars for the iOS mail experience by mirroring the web app's BIMI and domain-logo fallbacks, then tightened inbox row spacing and unread metadata so the mobile inbox reads closer to the web list. User-facing change. (apps/ios/src/features/mail/SenderAvatar.tsx, apps/ios/src/features/mail/ThreadListItem.tsx, apps/ios/src/features/mail/MessageCard.tsx, apps/ios/src/shared/config/env.ts, apps/ios/app/(app)/(mail)/[folder].tsx).

[2026-03-09] [Fix] Restored native thread body rendering by reading `decodedBody` in the message detail card when the server payload does not populate `processedHtml` or `body`. User-facing change. (apps/ios/src/features/mail/MessageCard.tsx).

[2026-03-10] [Fix] Resolved mobile Thread View UI issues including dark mode text, email clipping, large floating actions, and missing sender avatars (apps/ios/src/features/mail/MessageCard.tsx, apps/ios/src/features/mail/ThreadDetailPane.tsx, apps/ios/.env).

[2026-03-10] [Refactor] Flattened Thread View by removing nested cards and backgrounds around emails and notes in iOS app (apps/ios/src/features/mail/MessageCard.tsx, apps/ios/src/features/mail/ThreadDetailPane.tsx).

[2026-03-10] [UI Fix] Replicating web app Thread Layout in iOS. Added missing Reply All icon, matching exact header actions. Shifted floating action pills downwards. Fixed WebView horizontal overflow.

[2026-03-10] [UX Fix] Improved the native iOS inbox flow by replacing the placeholder ellipsis alert with real thread actions, moving notes below message content, hiding raw system labels behind friendlier names, adding inbox gesture discovery guidance, improving empty-state copy, and adding clearer search filter state with reset affordances. User-facing change. (apps/ios/src/features/mail/ThreadDetailPane.tsx, apps/ios/src/features/mail/ThreadListItem.tsx, apps/ios/app/(app)/(mail)/[folder].tsx, apps/ios/app/search.tsx).

[2026-03-10] [Fix] Normalized low-contrast message HTML in the native iOS thread view so dark mode no longer forces white text onto pale email backgrounds. The WebView now removes only broken light backgrounds or low-contrast text combinations instead of applying a blanket dark-mode text override. User-facing change. (apps/ios/src/features/mail/MessageCard.tsx).

[2026-03-10] [UX Fix] Added direct read-state controls to the native iOS mail triage flow: the inbox swipe menu now includes a read/unread action, and the thread header now exposes a dedicated mark read/unread button with optimistic state updates. User-facing change. (apps/ios/src/features/mail/SwipeableThreadRow.tsx, apps/ios/src/features/mail/ThreadDetailPane.tsx, apps/ios/app/(app)/(mail)/[folder].tsx).

[2026-03-10] [UI Polish] Refined the native iOS mail surfaces with a softer monochrome palette, denser typography, cleaner grouping, subtler accent usage, and more card-like hierarchy across inbox, search, and thread detail. User-facing change. (apps/ios/src/shared/theme/ThemeContext.tsx, apps/ios/src/features/mail/ThreadListItem.tsx, apps/ios/src/features/mail/MessageCard.tsx, apps/ios/src/features/mail/ThreadDetailPane.tsx, apps/ios/src/features/mail/SwipeableThreadRow.tsx, apps/ios/src/features/mail/SenderAvatar.tsx, apps/ios/app/(app)/(mail)/[folder].tsx, apps/ios/app/search.tsx).

[2026-03-11] [Fix] Corrected the optimistic read/unread rollback wiring in the native iOS swipe and thread-detail mutations so the new triage controls compile cleanly without changing their behavior. Architectural safety fix. (apps/ios/src/features/mail/SwipeableThreadRow.tsx, apps/ios/src/features/mail/ThreadDetailPane.tsx).

[2026-03-11] [UX Fix] Removed the inbox gesture tip banner, changed the mail compose header button from `+` to a pencil, shifted the remaining native mail palette away from blue/slate tints toward warmer neutrals, and updated sender-avatar fallbacks to request domain logos without generic placeholder fallbacks so missing logos render initials instead of the broken-person icon. User-facing change. (apps/ios/app/(app)/(mail)/[folder].tsx, apps/ios/src/shared/theme/ThemeContext.tsx, apps/ios/src/features/mail/SenderAvatar.tsx).

[2026-03-11] [UI Polish] Reworked the native iOS inbox into a cleaner divided list instead of stacked cards and redesigned the inbox header to foreground account identity with the signed-in avatar plus unread-count status, while preserving search and compose in a secondary action strip. User-facing change. (apps/ios/src/features/mail/ThreadListItem.tsx, apps/ios/app/(app)/(mail)/[folder].tsx).

[2026-03-31] [Feature] Expanded the active web app mail shell toward native parity by adding first-class `/mail/home`, `/mail/tasks`, `/mail/calendar`, `/mail/search`, and `/mail/chat` routes in `apps/mail`, switching `/mail` to land on Home, and upgrading the sidebar navigation to expose the same primary surfaces with expandable Email children. User-facing change. (apps/mail/app/routes.ts, apps/mail/app/(routes)/mail/page.tsx, apps/mail/app/(routes)/mail/home/page.tsx, apps/mail/app/(routes)/mail/tasks/page.tsx, apps/mail/app/(routes)/mail/calendar/page.tsx, apps/mail/app/(routes)/mail/search/page.tsx, apps/mail/app/(routes)/mail/chat/page.tsx, apps/mail/components/ui/nav-main.tsx, apps/mail/components/ui/app-sidebar.tsx, apps/mail/config/navigation.ts).

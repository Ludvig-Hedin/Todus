# Web → Native Parity Checklist (Living Document)

> **Last updated:** 2026-02-21
>
> **Purpose:** Single source of truth for ensuring the React Native apps (iOS, Android, macOS) achieve 1:1 feature, UI, and behavior parity with the existing React web app (`apps/mail`).

---

## Current State Assessment

> [!CAUTION]
> **The current native app (`apps/native`) is 100% WebView-based.** It wraps the web app in `react-native-webview` with a thin native auth layer. There are **zero truly native screens** beyond `LoginScreen`. All tasks marked "DONE" in `TASK.md` (M1-M7) refer to this WebView shell, not truly native UI implementations.

### What Exists (Native)

- `LoginScreen.tsx` — native login with provider discovery + OAuth handoff
- `WebAppScreen.tsx` — WebView wrapper that loads the entire web app
- `WebAuthScreen.tsx` — WebView for OAuth callback
- `PublicWebScreen.tsx` — WebView for public pages
- `@zero/design-tokens` — extracted color/typography/spacing tokens
- `@zero/ui-native` — 3 primitive components (Button, Screen, TextField)
- `@zero/api-client` — tRPC client + auth helpers (shared)
- `@zero/shared` — shared types

### What Must Be Built

- **ALL screens must be rebuilt as truly native React Native components**
- All 57+ shadcn UI components need native equivalents
- All 20 mail feature components (complex: mail-display 64KB, mail-list 42KB, thread-display 37KB)
- All 20 compose/editor components (Tiptap editor — biggest challenge)
- All 11 settings screens
- All public/legal pages (can remain WebView — acceptable)
- AI chat sidebar
- Voice integration

---

## A) Parity Dashboard

| Category | Total Items | ✅ Complete | 🟡 Partial | 🔴 Missing | ⚠️ Blocked |
|----------|------------|------------|-----------|-----------|------------|
| **Screens (Routes)** | 28 | 0 | 1 (Login) | 27 | 0 |
| **UI Components (Core)** | 57 | 0 | 3 (Button, Screen, TextField) | 54 | 0 |
| **Mail Feature Components** | 20 | 0 | 0 | 20 | 0 |
| **Compose/Editor Components** | 20 | 0 | 0 | 20 | ⚠️ 1 (Tiptap needs RN alternative) |
| **Custom Hooks** | 31 | 0 | 0 | 31 | 0 |
| **Workflows (E2E)** | 12 | 0 | 1 (Login) | 11 | 0 |
| **Integrations** | 10 | 0 | 2 (API client, Auth) | 8 | 0 |
| **TOTAL** | **178** | **0** | **7** | **171** | **1** |

---

## B) Screen-by-Screen Parity Checklist

### Screen: `/` (Landing/Index) → RN: `LandingScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (Geist font family, size scale, weights, line height)
- [ ] Colors match web (semantic tokens, gradients, borders, shadows)
- [ ] Components match web (CTA button, hero section, auth-redirect logic)
- [ ] Navigation matches (auto-redirect to `/mail/inbox` if authenticated)
- [ ] Data loaded matches web (auth state check)
- [ ] Loading states match web
- [ ] Empty states match web
- [ ] Error states match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

---

### Screen: `/home` (Home/Landing) → RN: `HomeScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS

- [ ] Layout matches web
- [ ] Typography matches web
- [ ] Colors match web
- [ ] Components match web (hero, features, pricing CTA)
- [ ] Navigation matches
- [ ] Data loaded matches web
- [ ] Loading states match web
- [ ] Empty states match web
- [ ] Error states match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [ ] Screenshots captured

---

### Screen: `/login` → RN: `LoginScreen`

**Status:** 🟡 Partial (native login exists but UI doesn't match web)
**Platforms:** iOS / Android / macOS

- [ ] Layout matches web (spacing, alignment)
- [ ] Typography matches web (Geist font)
- [ ] Colors match web (tokens)
- [x] Components: provider buttons exist
- [x] Navigation: auth flow triggers
- [x] Data loaded: provider list from `GET /api/public/providers`
- [ ] Loading states match web (spinner placement)
- [ ] Empty states match web (no providers available)
- [ ] Error states match web (OAuth failure messages)
- [ ] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [ ] Screenshots captured

---

### Screen: `/about` → RN: `AboutScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS
**Note:** Can use WebView for public pages (acceptable trade-off)

- [ ] Layout matches web
- [ ] Typography matches web
- [ ] Colors match web
- [ ] Components match web
- [ ] Navigation matches
- [ ] Data loaded matches web
- [ ] Screenshots captured

---

### Screen: `/terms` → RN: `TermsScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS
**Note:** Can use WebView for legal pages

- [ ] Layout matches web
- [ ] Navigation matches
- [ ] Screenshots captured

---

### Screen: `/pricing` → RN: `PricingScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS

- [ ] Layout matches web
- [ ] Typography matches web
- [ ] Colors match web
- [ ] Components match web (pricing cards, switch, dialog)
- [ ] Navigation matches (upgrade flow)
- [ ] Data loaded matches web (billing state from backend)
- [ ] Loading states match web
- [ ] Error states match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [ ] Screenshots captured

---

### Screen: `/privacy` → RN: `PrivacyScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS
**Note:** Can use WebView for legal pages

- [ ] Layout matches web
- [ ] Navigation matches
- [ ] Screenshots captured

---

### Screen: `/contributors` → RN: `ContributorsScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS

- [ ] Layout matches web (contributor grid, GitHub stats)
- [ ] Data loaded matches web (GitHub API)
- [ ] Loading states match web
- [ ] Screenshots captured

---

### Screen: `/hr` → RN: `HRScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS

- [ ] Layout matches web
- [ ] Screenshots captured

---

### Screen: `/developer` → RN: `DeveloperScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS

- [ ] Layout matches web
- [ ] Navigation matches
- [ ] Screenshots captured

---

### Screen: `/mail` (redirect → `/mail/inbox`) → RN: `MailRedirectScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS

- [ ] Redirect behavior matches web
- [ ] Deep link support

---

### Screen: `/mail/:folder` (Main Mailbox) → RN: `MailFolderScreen`

**Status:** 🔴 Missing — **CRITICAL SCREEN**
**Platforms:** iOS / Android / macOS

This is the most complex screen in the app. Web components involved:

- `mail.tsx` (30KB) — main shell with sidebar, list, thread display
- `mail-list.tsx` (42KB) — thread list with pagination, selection, bulk actions
- `mail-display.tsx` (64KB) — thread display with messages, attachments, actions
- `thread-display.tsx` (37KB) — detailed thread rendering
- `app-sidebar.tsx` (9KB) — folder sidebar with counts
- `ai-sidebar.tsx` (20KB) — AI chat panel
- `note-panel.tsx` (33KB) — notes/annotations panel
- `nav-main.tsx` (12KB) — main navigation items
- `nav-user.tsx` (30KB) — user profile/settings in nav

Checklist:

- [ ] **Sidebar** — folder list with unread counts, labels section, user menu
- [ ] **Mail List** — thread preview cards with sender, subject, snippet, date, labels
- [ ] **Thread Detail** — message rendering with HTML email content
- [ ] **Mail Actions** — read/unread, star, important, archive, delete, spam, move, label
- [ ] **Bulk Actions** — select all, select multiple, batch operations
- [ ] **Search** — search bar with filters
- [ ] **Compose button** — FAB or toolbar button
- [ ] **AI Sidebar toggle** — chat panel access
- [ ] **Notes Panel** — notes/annotations for threads
- [ ] Layout matches web (3-column: sidebar + list + thread OR 2-panel on mobile)
- [ ] Typography matches web (Geist font)
- [ ] Colors match web (all semantic tokens)
- [ ] Navigation: folder switching, back behavior, deep links
- [ ] Data loaded: same tRPC endpoints (`mail.getThreads`, `mail.getThread`, etc.)
- [ ] Loading states: skeletons for list and thread (see `mail-skeleton.tsx`)
- [ ] Empty states: "No messages" with visual
- [ ] Error states: network/auth errors with retry
- [ ] Optimistic updates: same behavior as web (`use-optimistic-actions.ts`, 17KB)
- [ ] Pagination: infinite scroll or paginated list
- [ ] Pull-to-refresh
- [ ] Swipe actions (native-specific enhancement)
- [ ] Accessibility parity (labels, focus order, VoiceOver/TalkBack)
- [ ] Performance: smooth scrolling on 100+ threads, no jank
- [ ] Screenshots captured

---

### Screen: `/mail/compose` → RN: `ComposeScreen`

**Status:** 🔴 Missing — **HIGH COMPLEXITY**
**Platforms:** iOS / Android / macOS

Web components involved:

- `email-composer.tsx` (43KB) — full compose UI
- `editor.tsx` (11KB) — Tiptap-based rich text editor
- `create-email.tsx` (10KB) — email creation logic
- `recipient-autosuggest.tsx` (10KB) — contact autocomplete
- `toolbar.tsx` (10KB) — formatting toolbar
- `template-button.tsx` (9KB) — email templates
- `schedule-send-picker.tsx` (7KB) — schedule send UI
- Various editor extensions and formatting components

Checklist:

- [ ] **Recipients** — To, CC, BCC with autosuggest
- [ ] **Subject line** — text input
- [ ] **Rich text editor** — bold, italic, lists, links, code, formatting ⚠️ Tiptap replacement needed
- [ ] **Attachments** — pick, upload, preview, remove
- [ ] **Templates** — template selection and insertion
- [ ] **AI compose** — AI-assisted writing (uses `ai-chat.tsx`, 19KB)
- [ ] **Schedule send** — calendar picker for delayed send
- [ ] **Undo send** — undo window after send
- [ ] **Draft auto-save** — periodic draft persistence
- [ ] **Image compression settings** — compression options
- [ ] Layout matches web
- [ ] Typography matches web
- [ ] Colors match web
- [ ] Navigation: modal presentation, dismiss behavior
- [ ] Data loaded: drafts, templates, contacts
- [ ] Loading states match web
- [ ] Error states: send failure, draft save failure
- [ ] Form validation: required recipients, valid emails
- [ ] Keyboard behavior: proper keyboard avoidance, return key behavior
- [ ] Accessibility parity
- [ ] Performance acceptable
- [ ] Screenshots captured

---

### Screen: `/mail/create` → RN: `MailCreateRedirectScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS

- [ ] Redirect to compose screen matches web
- [ ] Deep link support for mailto: links

---

### Screen: `/mail/under-construction/:path` → RN: `UnderConstructionScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS

- [ ] Placeholder UI matches web
- [ ] Path parameter display

---

### Screen: `/settings` (redirect → `/settings/general`) → RN: `SettingsRedirectScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS

- [ ] Redirect behavior matches web

---

### Screen: `/settings/general` → RN: `SettingsGeneralScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS

- [ ] Layout matches web (form layout with `settings-content.tsx`)
- [ ] Typography matches web
- [ ] Colors match web
- [ ] All form fields match web (tRPC `settings.*` mutations)
- [ ] Loading states match web
- [ ] Error states match web
- [ ] Form validation matches web
- [ ] Persistence matches (same backend calls)
- [ ] Accessibility parity
- [ ] Screenshots captured

---

### Screen: `/settings/appearance` → RN: `SettingsAppearanceScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS

- [ ] Theme switching (light/dark/system)
- [ ] Layout density options
- [ ] Color scheme preview
- [ ] All form fields match web
- [ ] Persistence matches
- [ ] Screenshots captured

---

### Screen: `/settings/connections` → RN: `SettingsConnectionsScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS

- [ ] Connection list display
- [ ] Add/remove/set-default connection actions
- [ ] OAuth reconnect flow
- [ ] Loading/error states
- [ ] Screenshots captured

---

### Screen: `/settings/labels` → RN: `SettingsLabelsScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS

- [ ] Label CRUD operations
- [ ] Color picker for labels
- [ ] Drag-to-reorder
- [ ] Search/filter labels
- [ ] Screenshots captured

---

### Screen: `/settings/categories` → RN: `SettingsCategoriesScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS

- [ ] Category configuration
- [ ] Toggle categories
- [ ] Screenshots captured

---

### Screen: `/settings/notifications` → RN: `SettingsNotificationsScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS

- [ ] Notification preferences form
- [ ] Push notification permission request (native)
- [ ] Screenshots captured

---

### Screen: `/settings/privacy` → RN: `SettingsPrivacyScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS

- [ ] Privacy controls
- [ ] Data sharing preferences
- [ ] Screenshots captured

---

### Screen: `/settings/security` → RN: `SettingsSecurityScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS

- [ ] Security settings
- [ ] Password/auth management
- [ ] Screenshots captured

---

### Screen: `/settings/shortcuts` → RN: `SettingsShortcutsScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS (keyboard shortcuts primarily macOS)

- [ ] Keyboard shortcut reference
- [ ] Platform-appropriate shortcuts (macOS: ⌘, iOS/Android: may omit or adapt)
- [ ] Screenshots captured

---

### Screen: `/settings/danger-zone` → RN: `SettingsDangerZoneScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS

- [ ] Account deletion flow
- [ ] Confirmation dialogs
- [ ] Destructive action styling (red/warning)
- [ ] Screenshots captured

---

### Screen: `/settings/*` (fallback) → RN: `SettingsFallbackScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS

- [ ] Fallback/not-found handling

---

### Screen: `/*` (Not Found) → RN: `NotFoundScreen`

**Status:** 🔴 Missing
**Platforms:** iOS / Android / macOS

- [ ] 404 display matches web
- [ ] Navigation back to home/mail

---

## C) Component Parity Checklist

### Core UI Primitives (from `components/ui/`)

| Web Component | RN Component | Status |
|--------------|-------------|--------|
| `button.tsx` | `@zero/ui-native/Button` | 🟡 Exists, needs visual parity pass |
| `input.tsx` | `@zero/ui-native/TextField` | 🟡 Exists, needs visual parity pass |
| `accordion.tsx` | — | 🔴 Missing |
| `alert.tsx` | — | 🔴 Missing |
| `animated-number.tsx` | — | 🔴 Missing |
| `avatar.tsx` | — | 🔴 Missing |
| `badge.tsx` | — | 🔴 Missing |
| `bimi-avatar.tsx` | — | 🔴 Missing |
| `calendar.tsx` | — | 🔴 Missing |
| `card.tsx` | — | 🔴 Missing |
| `chart.tsx` | — | 🔴 Missing |
| `checkbox.tsx` | — | 🔴 Missing |
| `collapsible.tsx` | — | 🔴 Missing |
| `command.tsx` | — | 🔴 Missing |
| `context-menu.tsx` | — | 🔴 Missing (use native context menu) |
| `dialog.tsx` | — | 🔴 Missing |
| `drawer.tsx` | — | 🔴 Missing |
| `dropdown-menu.tsx` | — | 🔴 Missing |
| `envelop.tsx` | — | 🔴 Missing |
| `form.tsx` | — | 🔴 Missing |
| `gauge.tsx` | — | 🔴 Missing |
| `input-otp.tsx` | — | 🔴 Missing |
| `label.tsx` | — | 🔴 Missing |
| `navigation-menu.tsx` | — | 🔴 Missing (use @react-navigation) |
| `page-header.tsx` | — | 🔴 Missing |
| `popover.tsx` | — | 🔴 Missing |
| `pricing-dialog.tsx` | — | 🔴 Missing |
| `pricing-switch.tsx` | — | 🔴 Missing |
| `progress.tsx` | — | 🔴 Missing |
| `prompts-dialog.tsx` | — | 🔴 Missing |
| `radio-group.tsx` | — | 🔴 Missing |
| `recipient-autosuggest.tsx` | — | 🔴 Missing |
| `recursive-folder.tsx` | — | 🔴 Missing |
| `resizable.tsx` | — | 🔴 Missing (macOS split-pane) |
| `responsive-modal.tsx` | — | 🔴 Missing |
| `scroll-area.tsx` | — | 🔴 Missing (native ScrollView) |
| `select.tsx` | — | 🔴 Missing |
| `separator.tsx` | — | 🔴 Missing |
| `settings-content.tsx` | — | 🔴 Missing |
| `sheet.tsx` | — | 🔴 Missing |
| `sidebar.tsx` | — | 🔴 Missing |
| `sidebar-labels.tsx` | — | 🔴 Missing |
| `sidebar-toggle.tsx` | — | 🔴 Missing |
| `skeleton.tsx` | — | 🔴 Missing |
| `spinner.tsx` | — | 🔴 Missing |
| `switch.tsx` | — | 🔴 Missing |
| `tabs.tsx` | — | 🔴 Missing |
| `text-shimmer.tsx` | — | 🔴 Missing |
| `textarea.tsx` | — | 🔴 Missing |
| `toast.tsx` | — | 🔴 Missing |
| `toggle.tsx` | — | 🔴 Missing |
| `toggle-group.tsx` | — | 🔴 Missing |
| `tooltip.tsx` | — | 🔴 Missing (native: long-press tooltip) |

### Complex Feature Components (from `components/mail/`)

| Web Component | Size | RN Component | Status | Notes |
|--------------|------|-------------|--------|-------|
| `mail.tsx` | 30KB | — | 🔴 | Main shell (sidebar+list+thread) |
| `mail-list.tsx` | 42KB | — | 🔴 | Thread list with bulk ops |
| `mail-display.tsx` | 64KB | — | 🔴 | Thread display, attachments, actions |
| `thread-display.tsx` | 37KB | — | 🔴 | Detailed thread renderer |
| `note-panel.tsx` | 33KB | — | 🔴 | Notes/annotations panel |
| `ai-sidebar.tsx` | 20KB | — | 🔴 | AI chat sidebar |
| `nav-user.tsx` | 30KB | — | 🔴 | User nav with settings/logout |
| `nav-main.tsx` | 12KB | — | 🔴 | Main folder navigation |
| `reply-composer.tsx` | 10KB | — | 🔴 | Reply inline compose |
| `mail-content.tsx` | 6KB | — | 🔴 | Content rendering |
| `mail-skeleton.tsx` | 7KB | — | 🔴 | Loading skeletons |
| `select-all-checkbox.tsx` | 4KB | — | 🔴 | Bulk select control |
| `attachments-accordion.tsx` | 4KB | — | 🔴 | Attachment display |
| `snooze-dialog.tsx` | 3KB | — | 🔴 | Snooze picker |
| `render-labels.tsx` | 3KB | — | 🔴 | Label badges |
| `optimistic-thread-state.tsx` | 3KB | — | 🔴 | Optimistic state UI |
| `attachment-dialog.tsx` | 3KB | — | 🔴 | Attachment preview |
| `navbar.tsx` | 3KB | — | 🔴 | Top navbar |
| `email-verification-badge.tsx` | 1KB | — | 🔴 | Verification indicator |
| `data.tsx` | 15KB | — | 🔴 | Data utilities/constants |

### Compose/Editor Components (from `components/create/`)

| Web Component | Size | RN Component | Status | Notes |
|--------------|------|-------------|--------|-------|
| `email-composer.tsx` | 43KB | — | 🔴 | Full compose UI |
| `ai-chat.tsx` | 19KB | — | 🔴 | AI compose assistant |
| `editor.tsx` | 11KB | — | ⚠️ Blocked | Tiptap → RN editor replacement needed |
| `toolbar.tsx` | 10KB | — | 🔴 | Formatting toolbar |
| `recipient-autosuggest.tsx` (in ui/) | 10KB | — | 🔴 | Contact autocomplete |
| `template-button.tsx` | 9KB | — | 🔴 | Template picker |
| `create-email.tsx` | 10KB | — | 🔴 | Email creation logic |
| `editor-autocomplete.ts` | 8KB | — | ⚠️ Blocked | Editor-specific |
| `schedule-send-picker.tsx` | 7KB | — | 🔴 | Schedule send calendar |
| `editor-buttons.tsx` | 5KB | — | 🔴 | Editor formatting buttons |
| `editor.colors.tsx` | 5KB | — | 🔴 | Color picker |
| `image-compression-settings.tsx` | 3KB | — | 🔴 | Image settings |
| `uploaded-file-icon.tsx` | 2KB | — | 🔴 | File type icons |
| `editor.text-buttons.tsx` | 2KB | — | 🔴 | Text formatting |
| `slash-command.tsx` | 2KB | — | 🔴 | Slash commands |
| `editor-menu.tsx` | 1KB | — | 🔴 | Editor menu |
| `email-phrases.ts` | 2KB | — | 🔴 | Quick phrases |

---

## D) Workflow Parity Checklist (End-to-End)

### Workflow: Auth — Signup / Login / Logout

**Status:** 🟡 Partial

- [x] Login with social providers (Google OAuth)
- [x] Session token storage (AsyncStorage)
- [x] Session restore on app restart
- [x] Logout with session cleanup
- [ ] Login matches web UI layout/styling
- [ ] Error messages match web (auth failure, network error)
- [ ] Session refresh handling verified end-to-end
- [ ] "Remember me" behavior parity
- [ ] Deep link back from OAuth callback
- [ ] E2E test exists

### Workflow: Read Mail — Inbox → Thread → Actions

**Status:** 🔴 Missing

- [ ] Open inbox, see thread list
- [ ] Tap thread to see full conversation
- [ ] Mark read/unread
- [ ] Star/unstar
- [ ] Archive
- [ ] Delete
- [ ] Move to spam
- [ ] Apply label
- [ ] Move to folder
- [ ] Same tRPC calls in same order
- [ ] Optimistic updates with rollback
- [ ] Pull-to-refresh
- [ ] Empty inbox state
- [ ] Network error handling
- [ ] E2E test exists

### Workflow: Compose — New Email / Reply / Forward

**Status:** 🔴 Missing

- [ ] Open compose (new email)
- [ ] Add recipients with autosuggest
- [ ] Add CC/BCC
- [ ] Enter subject
- [ ] Write body with formatting
- [ ] Attach files
- [ ] Send email
- [ ] Undo send
- [ ] Reply to thread
- [ ] Reply all
- [ ] Forward
- [ ] Draft auto-save
- [ ] Draft restore
- [ ] Draft delete
- [ ] Schedule send
- [ ] Use template
- [ ] AI compose assistance
- [ ] E2E test exists

### Workflow: Search / Filter / Sort

**Status:** 🔴 Missing

- [ ] Search bar with text input
- [ ] Filter by folder/label
- [ ] Sort by date/sender
- [ ] Search results list
- [ ] Same API calls
- [ ] Loading/empty/error states
- [ ] E2E test exists

### Workflow: Label Management

**Status:** 🔴 Missing

- [ ] Create label
- [ ] Edit label (name, color)
- [ ] Delete label
- [ ] Apply label to thread
- [ ] Remove label from thread
- [ ] Label filter in sidebar
- [ ] E2E test exists

### Workflow: Connections Management

**Status:** 🔴 Missing

- [ ] List email connections
- [ ] Add new connection (OAuth)
- [ ] Set default connection
- [ ] Disconnect
- [ ] Reconnect
- [ ] E2E test exists

### Workflow: Settings — All Settings Screens

**Status:** 🔴 Missing

- [ ] General settings save/load
- [ ] Appearance (theme) switch persists
- [ ] Notifications preferences save
- [ ] Privacy controls save
- [ ] Security settings save
- [ ] Shortcuts reference displays
- [ ] Danger zone (account deletion) with confirmation
- [ ] All forms persist to same API
- [ ] E2E test exists

### Workflow: AI Chat

**Status:** 🔴 Missing

- [ ] Open AI sidebar/panel
- [ ] Send message
- [ ] Receive streaming response
- [ ] AI context (thread-aware)
- [ ] Close AI panel
- [ ] Same API calls
- [ ] E2E test exists

### Workflow: Voice

**Status:** 🔴 Missing

- [ ] Microphone permission request
- [ ] Start voice conversation
- [ ] Stop voice conversation
- [ ] Voice transcript display
- [ ] ElevenLabs integration
- [ ] E2E test exists

### Workflow: Notes

**Status:** 🔴 Missing

- [ ] Open note panel on thread
- [ ] Create note
- [ ] Edit note
- [ ] Delete note
- [ ] Notes persist via tRPC
- [ ] E2E test exists

### Workflow: Billing / Pricing

**Status:** 🔴 Missing

- [ ] View pricing page
- [ ] View current subscription state
- [ ] Upgrade flow (Autumn billing via backend)
- [ ] Downgrade/cancel
- [ ] E2E test exists

### Workflow: Snooze

**Status:** 🔴 Missing

- [ ] Open snooze dialog on thread
- [ ] Select snooze time
- [ ] Snooze persists
- [ ] Snoozed thread reappears at correct time
- [ ] E2E test exists

---

## E) Integrations Parity Checklist

### Better Auth (Authentication)

**Status:** 🟡 Partial

- [x] Native auth adapter exists (`native-auth.ts`)
- [x] Bearer token auth flow
- [x] Session validation (`validateNativeBearerSession`)
- [x] Sign-out (`signOutNativeSession`)
- [ ] Verified on iOS
- [ ] Verified on Android
- [ ] Verified on macOS
- [ ] Token refresh fully tested
- [ ] Deep link OAuth callbacks configured

### tRPC (API Layer)

**Status:** 🟡 Partial

- [x] tRPC client exists (`@zero/api-client`)
- [x] `httpBatchLink` with superjson
- [x] Bearer token header injection
- [ ] All 16 router domains verified in native context
- [ ] Error handling parity (401 → logout)
- [ ] Offline/retry behavior

### PostHog (Analytics)

**Status:** 🔴 Missing

- [ ] `posthog-react-native` installed and configured
- [ ] Same event names/properties as web
- [ ] Screen view tracking
- [ ] Feature flags synced
- [ ] Verified on all platforms

### Sentry (Error Reporting)

**Status:** 🔴 Missing

- [ ] `@sentry/react-native` installed and configured
- [ ] Crash reporting verified
- [ ] Performance monitoring enabled
- [ ] Source maps uploaded for production
- [ ] Verified on all platforms

### Intercom (Support)

**Status:** 🔴 Missing

- [ ] Native Intercom SDK wrapper
- [ ] User identification
- [ ] Help center access
- [ ] Chat support
- [ ] Verified on all platforms

### Autumn (Billing)

**Status:** 🔴 Missing

- [ ] Backend-driven billing state query
- [ ] Subscription status display
- [ ] Upgrade/downgrade CTA
- [ ] Verified on all platforms

### ElevenLabs (Voice)

**Status:** 🔴 Missing

- [ ] Native audio permission handling
- [ ] RN-compatible ElevenLabs client
- [ ] Voice conversation start/stop
- [ ] Transcript display
- [ ] Verified on all platforms

### Dub (Analytics Links)

**Status:** 🔴 Missing

- [ ] Link tracking (if applicable to native)

### GitHub API (Contributors)

**Status:** 🔴 Missing

- [ ] Contributors page data fetch
- [ ] Stars display

### Tiptap → RN Editor

**Status:** ⚠️ Blocked

- [ ] Evaluate RN rich text editor alternatives:
  - `react-native-pell-rich-editor`
  - `react-native-rich-editor`
  - `@10play/tentap-editor` (Tiptap-based for RN)
  - Custom WebView-based Tiptap wrapper
- [ ] Selected solution supports: bold, italic, lists, links, code blocks
- [ ] Selected solution supports image embedding
- [ ] Formatting toolbar parity
- [ ] Verified on all platforms

---

## F) Visual Regression & "99% Same" Proof

### Required Procedure

- [ ] For every screen: capture reference screenshots on web
- [ ] For every screen: capture screenshots on iOS
- [ ] For every screen: capture screenshots on Android
- [ ] For every screen: capture screenshots on macOS
- [ ] Compare and record differences
- [ ] Log acceptable differences (e.g., native switch, native navigation bar) with justification
- [ ] Maintain `/parity_screenshots/` folder with naming convention:
  `ScreenName__web.png`, `ScreenName__ios.png`, `ScreenName__android.png`, `ScreenName__macos.png`

### Acceptable Divergences (Documented)

| Element | Web | Native | Justification |
|---------|-----|--------|---------------|
| Toggle/Switch | shadcn toggle | Native `Switch` | Platform convention |
| Context Menu | Radix context-menu | Native long-press menu | Platform convention |
| Navigation | React Router | @react-navigation stack/tabs | Platform convention |
| Sheet/Drawer | Radix sheet | `@gorhom/bottom-sheet` | Better native UX |
| Date Picker | Calendar popover | Native date picker | Platform convention |
| Select/Dropdown | Radix select | Native picker / action sheet | Platform convention |
| Tooltip | Radix tooltip | Long-press hint | Touch paradigm |
| Scroll Area | Radix scroll-area | Native ScrollView | Native default |
| Font | Geist Variable | Geist (bundled) or system font | Font availability |
| Keyboard Shortcuts | Hotkey library | RN key handlers (macOS only) | Platform limitation |

---

## G) Acceptance Criteria (Definition of Done)

App is considered "parity complete" only when:

- [ ] 100% of web routes have RN equivalents (or explicitly documented as WebView/deprecated)
- [ ] All 12 workflows pass on iOS
- [ ] All 12 workflows pass on Android
- [ ] All 12 workflows pass on macOS
- [ ] No 🔴 items remain in the parity dashboard
- [ ] Only documented, justified UI differences remain
- [ ] Performance baselines met:
  - [ ] App cold start < 2s
  - [ ] Thread list scroll: 60fps, no jank
  - [ ] Thread open: < 500ms
  - [ ] Navigation transitions: < 300ms
- [ ] Release builds succeed:
  - [ ] iOS release build (Xcode Archive)
  - [ ] Android release build (signed APK/AAB)
  - [ ] macOS release build
- [ ] All E2E tests pass
- [ ] Visual regression screenshots approved

---

## Top 10 Highest-Risk Parity Areas

1. **Rich Text Editor (Tiptap → RN)** — No direct RN equivalent for Tiptap. Need evaluation of `@10play/tentap-editor` or WebView fallback. This blocks compose feature parity.

2. **Mail Display (64KB component)** — HTML email rendering in RN requires `react-native-webview` per-message or a custom HTML renderer. Performance with many messages is a risk.

3. **Mail List Performance (42KB component)** — Thread list with 100+ items, bulk selection, swipe actions, optimistic updates. Requires `FlashList` + careful virtualization.

4. **Thread Display (37KB component)** — Complex nested message rendering with HTML content, attachments, quoted text folding.

5. **AI Sidebar (20KB component)** — Streaming AI responses, context-aware chat, tool execution display.

6. **Note Panel (33KB component)** — Rich note editing alongside thread. May need its own editor solution.

7. **macOS Split-Pane Layout** — Desktop-class 3-column layout (sidebar + list + detail) is web's resizable panels. RN macOS needs custom implementation.

8. **Optimistic Updates (17KB hook)** — Complex optimistic state management with rollback. Must match web behavior exactly.

9. **Voice Integration (ElevenLabs)** — Native audio permissions + streaming audio + transcript display. Platform-specific implementation needed.

10. **Nav User Menu (30KB component)** — Complex user menu with connections, themes, billing state, logout. Large component to rebuild.

---

## Recommended Test Strategy

### Unit Tests (Logic)

- **What:** Shared schema/type utilities, storage adapters, auth token handling, design token resolution, data transformers
- **How:** `jest` in `packages/shared`, `packages/api-client`, `packages/design-tokens`
- **Run:** `pnpm --filter @zero/shared test` / `pnpm --filter @zero/api-client test`

### Integration Tests (API)

- **What:** tRPC client adapter with mock server, auth flow (login → token → API call → logout), session bootstrap/restore, optimistic update rollback
- **How:** `jest` + `msw` (mock service worker) for tRPC endpoint mocking
- **Run:** `pnpm --filter @zero/native test`

### E2E Tests (Critical Flows)

- **What:** Login → Inbox → Open Thread → Reply → Send → Verify
- **How:** Detox (iOS/Android) or Maestro (cross-platform)
- **Recommended:** Maestro for simpler setup: `maestro test flows/`
- **Critical flows to test:**
  1. Login with Google → lands on inbox
  2. Open thread → read message → mark unread
  3. Compose new email → add recipient → send → undo
  4. Settings → change theme → verify persistence
  5. Search → filter → open result

### Manual QA Script (Release Candidates)

For each release candidate, execute on all 3 platforms:

1. **Fresh install** — App launches, shows login screen
2. **Login** — Google OAuth succeeds, lands on inbox
3. **Mail list** — Threads load, scroll is smooth, pull-to-refresh works
4. **Thread detail** — Open thread, messages render, HTML content displays
5. **Actions** — Star, archive, delete, mark unread — all work with undo
6. **Compose** — New email, add recipients, format text, attach file, send
7. **Reply** — Open thread, reply inline, send
8. **Settings** — Navigate all settings screens, change theme, verify persistence
9. **AI chat** — Open AI sidebar, send message, receive response
10. **Logout** — Sign out, verify session cleared, back to login
11. **Performance** — No visible jank on scroll, smooth transitions
12. **Dark mode** — Toggle dark mode, all screens render correctly
13. **Offline** — Airplane mode, verify graceful error handling

---

## Working Rules

- This checklist is a **living artifact**: update after every feature migration PR
- If any parity gap is found, create a task in `TASK.md` and link it from here
- Prefer objective verification (tests + screenshots) over opinions
- When updating: change status emoji, check boxes, add date stamps for completed items

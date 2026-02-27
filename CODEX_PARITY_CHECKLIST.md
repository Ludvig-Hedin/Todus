# PARITY_CHECKLIST.md

Last updated: 2026-02-21
Owner: Native migration team (QA + Mobile + Design Systems)

This is the living source of truth for React Web -> React Native parity (iOS, Android, macOS).

## Inventory Snapshot (Extracted From Repo)

### Route/Page Inventory (web)

Source: `apps/mail/app/routes.ts`, `packages/shared/src/index.ts`

- `/`
- `/home`
- `/login`
- `/about`
- `/terms`
- `/pricing`
- `/privacy`
- `/contributors`
- `/hr`
- `/developer`
- `/mail`
- `/mail/:folder`
- `/mail/compose`
- `/mail/create`
- `/mail/under-construction/:path`
- `/settings`
- `/settings/appearance`
- `/settings/connections`
- `/settings/danger-zone`
- `/settings/general`
- `/settings/labels`
- `/settings/categories`
- `/settings/notifications`
- `/settings/privacy`
- `/settings/security`
- `/settings/shortcuts`
- `/settings/*`
- `/*`

### Native Surface Inventory

Source: `apps/native/src/**`

- `LoginScreen` (native screen)
- `WebAuthScreen` (OAuth/auth WebView)
- `WebAppScreen` (authenticated app shell WebView)
- `PublicWebScreen` (public route WebView)
- Session/bootstrap/auth guard providers
- Route parity tests (`apps/native/__tests__/App.test.tsx`)

### Major UI Component Inventory (web)

Source: `apps/mail/components/**`

- Mail shell: sidebar, mail list, thread display, mail display
- Compose stack: email composer, reply composer, recipient autosuggest, schedule send
- Attachments: thread attachments, upload/remove/download UI
- Settings cards/forms (general, appearance, connections, labels, categories, notifications, privacy, security, shortcuts, danger zone)
- AI/voice: AI sidebar, voice button/provider
- Command/search: command palette, filters/search inputs
- Pricing/billing: pricing cards/dialog, billing actions
- Core primitives: button, input, textarea, select, dialog, sheet, drawer, toast, tabs, tooltip, switch, checkbox

### Critical Workflow Inventory

- Auth: provider discovery, social sign-in handoff, login, logout, session restore/refresh
- Mailbox browse: folder navigation, list pagination, thread open
- Thread actions: read/unread, archive/unarchive, spam/inbox, bin/restore/delete, star/important, snooze, labels
- Compose: new message, reply/reply-all/forward, recipient handling, attachments, send
- Draft lifecycle: create/save/restore/delete, undo-send behavior
- Search/filter/sort and command palette-driven search
- Settings + preferences persistence
- Connections management
- Billing upgrade + billing portal
- AI chat/search/compose assistance
- Voice assistant session

### Integration Inventory

- Better Auth (JWT/bearer/social)
- Google OAuth (+ server-side provider drivers)
- tRPC + React Query
- Sentry
- PostHog
- Dub analytics
- Intercom
- Autumn billing
- ElevenLabs voice
- OpenAI + Perplexity features (server)
- Twilio OTP (server)

### Env Vars / Flags Affecting Behavior

Source: `.env.example`, `apps/server/src/env.ts`, `apps/native/src/shared/config/env.ts`

- App URLs: `VITE_PUBLIC_APP_URL`, `VITE_PUBLIC_BACKEND_URL`, `ZERO_PUBLIC_WEB_URL`, `ZERO_PUBLIC_BACKEND_URL`
- Native routing/auth: `ZERO_PUBLIC_APP_ENTRY_PATH`, `ZERO_PUBLIC_AUTH_CALLBACK_URL`, `ZERO_PUBLIC_APP_NAME`
- Auth/OAuth: `BETTER_AUTH_SECRET`, `BETTER_AUTH_URL`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `MICROSOFT_CLIENT_ID`, `MICROSOFT_CLIENT_SECRET`
- Analytics/monitoring: `VITE_PUBLIC_POSTHOG_KEY`, `VITE_PUBLIC_POSTHOG_HOST`, Sentry DSN/tunnel config
- Billing: `AUTUMN_SECRET_KEY`
- AI: `OPENAI_API_KEY`, `OPENAI_MODEL`, `OPENAI_MINI_MODEL`, `PERPLEXITY_API_KEY`
- Voice: `VITE_PUBLIC_ELEVENLABS_AGENT_ID`, `ELEVENLABS_API_KEY`
- Messaging: `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_PHONE_NUMBER`, `RESEND_API_KEY`
- Infra/feature flags: `NODE_ENV`, `EARLY_ACCESS_ENABLED`, `USE_OPENAI`, `ENABLE_MEET`, `DISABLE_WORKFLOWS`, `THREAD_SYNC_*`

## A) Parity Dashboard

### Status Counts

| Category | ✅ Complete | 🟡 Partial | 🔴 Missing | ⚠️ Blocked |
|---|---:|---:|---:|---:|
| Screens | 0 | 28 | 0 | 0 |
| Components | 0 | 18 | 2 | 0 |
| Workflows | 0 | 10 | 2 | 1 |
| Integrations | 0 | 9 | 3 | 1 |

### Current Summary

- Current native strategy is **WebView parity shell**.
- This gives high UI fidelity quickly for many routes, but platform verification, screenshots, deep linking, and native SDK parity are still incomplete.
- Gap tasks linked in `TASK.md` under **Parity Gap Tasks (2026-02-21)**.

## B) Screen-by-Screen Parity Checklist

Platform baseline for entries below unless noted otherwise:

- iOS: implemented via RN shell + WebView, needs screenshot/perf/accessibility proof.
- Android: code path exists but not yet validated in this pass.
- macOS: implemented via RN macOS + WebView, keyboard/deep-link proof pending.

### Screen: `/` -> RN: `PublicWebScreen(path='/')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web (WebView renders same web route)
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches (direct entry/deep link path handling still pending)
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity (web events from embedded app)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/home` -> RN: `PublicWebScreen(path='/home')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/login` -> RN: `LoginScreen` + `WebAuthScreen`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [ ] Layout matches web (native login shell differs)
- [ ] Typography matches web
- [ ] Colors match web
- [ ] Components match web
- [x] Navigation matches (provider flow -> auth -> app shell)
- [x] Data loaded matches web (provider discovery + sign-in endpoint)
- [x] Loading states match web
- [ ] Empty states match web (provider-empty specific handling needs pass)
- [x] Error states match web
- [ ] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [ ] Analytics events parity (native auth events not instrumented separately)
- [ ] Screenshots captured

### Screen: `/about` -> RN: `PublicWebScreen(path='/about')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/terms` -> RN: `PublicWebScreen(path='/terms')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/pricing` -> RN: `PublicWebScreen(path='/pricing')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/privacy` -> RN: `PublicWebScreen(path='/privacy')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/contributors` -> RN: `PublicWebScreen(path='/contributors')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/hr` -> RN: `PublicWebScreen(path='/hr')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/developer` -> RN: `PublicWebScreen(path='/developer')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/mail` -> RN: `WebAppScreen(path='/mail')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches (deep links + nav state restoration still incomplete)
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/mail/:folder` -> RN: `WebAppScreen(path='/mail/:folder')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/mail/compose` -> RN: `WebAppScreen(path='/mail/compose')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/mail/create` -> RN: `WebAppScreen(path='/mail/create')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/mail/under-construction/:path` -> RN: `WebAppScreen(path='/mail/under-construction/:path')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/settings` -> RN: `WebAppScreen(path='/settings')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/settings/appearance` -> RN: `WebAppScreen(path='/settings/appearance')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/settings/connections` -> RN: `WebAppScreen(path='/settings/connections')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/settings/danger-zone` -> RN: `WebAppScreen(path='/settings/danger-zone')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/settings/general` -> RN: `WebAppScreen(path='/settings/general')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/settings/labels` -> RN: `WebAppScreen(path='/settings/labels')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/settings/categories` -> RN: `WebAppScreen(path='/settings/categories')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/settings/notifications` -> RN: `WebAppScreen(path='/settings/notifications')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/settings/privacy` -> RN: `WebAppScreen(path='/settings/privacy')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/settings/security` -> RN: `WebAppScreen(path='/settings/security')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/settings/shortcuts` -> RN: `WebAppScreen(path='/settings/shortcuts')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/settings/*` -> RN: `WebAppScreen(path='/settings/*')`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

### Screen: `/*` -> RN: `WebAppScreen/PublicWebScreen fallback`

**Status:** 🟡  
**Platforms:** iOS / Android / macOS

Checklist:

- [x] Layout matches web
- [x] Typography matches web
- [x] Colors match web
- [x] Components match web
- [ ] Navigation matches
- [x] Data loaded matches web
- [x] Loading states match web
- [x] Empty states match web
- [x] Error states match web
- [x] Forms match web
- [ ] Accessibility parity
- [ ] Performance acceptable
- [x] Analytics events parity
- [ ] Screenshots captured

## C) Component Parity Checklist

### Component: `AppSidebar` -> RN: `WebAppScreen(WebView)`

- [x] Props parity (same web component rendered)
- [x] Visual parity
- [ ] Interaction parity (hover/focus/mac shortcuts verification pending)
- [x] Disabled/loading states parity
- [x] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors in native shell

### Component: `NavMain`/`NavUser` -> RN: `WebAppScreen(WebView)`

- [x] Props parity
- [x] Visual parity
- [ ] Interaction parity
- [x] Disabled/loading states parity
- [x] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors in native shell

### Component: `MailList` -> RN: `WebAppScreen(WebView)`

- [x] Props parity
- [x] Visual parity
- [ ] Interaction parity (touch/scroll performance baseline pending)
- [x] Disabled/loading states parity
- [x] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors in native shell

### Component: `ThreadDisplay` -> RN: `WebAppScreen(WebView)`

- [x] Props parity
- [x] Visual parity
- [ ] Interaction parity
- [x] Disabled/loading states parity
- [x] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors in native shell

### Component: `MailDisplay` / `MailContent` -> RN: `WebAppScreen(WebView)`

- [x] Props parity
- [x] Visual parity
- [ ] Interaction parity (link/open behavior cross-platform pass pending)
- [x] Disabled/loading states parity
- [x] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors in native shell

### Component: `ReplyComposer` -> RN: `WebAppScreen(WebView)`

- [x] Props parity
- [x] Visual parity
- [ ] Interaction parity
- [x] Disabled/loading states parity
- [x] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors in native shell

### Component: `CreateEmail`/`EmailComposer` -> RN: `WebAppScreen(WebView)`

- [x] Props parity
- [x] Visual parity
- [ ] Interaction parity (keyboard/input accessory and file picker parity pending)
- [x] Disabled/loading states parity
- [x] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors in native shell

### Component: `RecipientAutosuggest` -> RN: `WebAppScreen(WebView)`

- [x] Props parity
- [x] Visual parity
- [ ] Interaction parity
- [x] Disabled/loading states parity
- [x] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors in native shell

### Component: `AttachmentsAccordion` / `AttachmentDialog` -> RN: `WebAppScreen(WebView)`

- [x] Props parity
- [x] Visual parity
- [ ] Interaction parity (native file chooser bridge validation pending)
- [x] Disabled/loading states parity
- [x] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors in native shell

### Component: `LabelDialog` / `SidebarLabels` -> RN: `WebAppScreen(WebView)`

- [x] Props parity
- [x] Visual parity
- [ ] Interaction parity
- [x] Disabled/loading states parity
- [x] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors in native shell

### Component: `SettingsCard` / `SettingsContent` -> RN: `WebAppScreen(WebView)`

- [x] Props parity
- [x] Visual parity
- [ ] Interaction parity
- [x] Disabled/loading states parity
- [x] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors in native shell

### Component: `PricingDialog` / `PricingCard` -> RN: `WebAppScreen(WebView)`

- [x] Props parity
- [x] Visual parity
- [ ] Interaction parity (native external checkout transitions pending)
- [x] Disabled/loading states parity
- [x] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors in native shell

### Component: `AISidebar` -> RN: `WebAppScreen(WebView)`

- [x] Props parity
- [x] Visual parity
- [ ] Interaction parity
- [x] Disabled/loading states parity
- [x] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors in native shell

### Component: `CommandPalette` -> RN: `WebAppScreen(WebView)`

- [x] Props parity
- [x] Visual parity
- [ ] Interaction parity (native keyboard events, macOS command routing pending)
- [x] Disabled/loading states parity
- [x] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors in native shell

### Component: `Search + Filter UI` -> RN: `WebAppScreen(WebView)`

- [x] Props parity
- [x] Visual parity
- [ ] Interaction parity
- [x] Disabled/loading states parity
- [x] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors in native shell

### Component: `Toast` -> RN: `WebAppScreen(WebView)`

- [x] Props parity
- [x] Visual parity
- [ ] Interaction parity
- [x] Disabled/loading states parity
- [x] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors in native shell

### Component: `Theme toggles` -> RN: `WebAppScreen(WebView)` + native shell controls

- [x] Props parity
- [x] Visual parity
- [ ] Interaction parity (native shell theme sync end-to-end pass pending)
- [x] Disabled/loading states parity
- [x] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors in native shell

### Component: `VoiceButton` -> RN: `No native equivalent yet`

- [ ] Props parity
- [ ] Visual parity
- [ ] Interaction parity
- [ ] Disabled/loading states parity
- [ ] Error/validation display parity
- [ ] Theming/token usage parity
- [ ] Unit tests for core behaviors

### Component: `HotkeyRecorder` / keyboard shortcut capture -> RN: `No native equivalent yet`

- [ ] Props parity
- [ ] Visual parity
- [ ] Interaction parity
- [ ] Disabled/loading states parity
- [ ] Error/validation display parity
- [ ] Theming/token usage parity
- [ ] Unit tests for core behaviors

## D) Workflow Parity Checklist (End-to-End)

### Workflow: Auth (provider discovery -> login -> logout -> restore/refresh)

- [x] Matches web steps exactly (same backend endpoints)
- [x] Handles same edge cases (failed provider load/auth failure)
- [x] Same backend calls in same order
- [x] Same data persisted (session + path)
- [x] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled equivalently
- [ ] E2E test exists (or manual test script documented)

### Workflow: Mailbox browse (folder -> list -> thread open)

- [x] Matches web steps exactly
- [x] Handles same edge cases
- [x] Same backend calls in same order
- [x] Same data persisted (web app behavior)
- [x] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled equivalently
- [ ] E2E test exists

### Workflow: Thread action CRUD (read/unread/star/archive/spam/bin/snooze/labels)

- [x] Matches web steps exactly
- [x] Handles same edge cases
- [x] Same backend calls in same order
- [x] Same data persisted
- [x] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled equivalently
- [ ] E2E test exists

### Workflow: Compose + reply/forward

- [x] Matches web steps exactly
- [x] Handles same edge cases
- [x] Same backend calls in same order
- [x] Same data persisted
- [x] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled equivalently
- [ ] E2E test exists

### Workflow: Draft lifecycle (create/save/restore/delete + undo-send)

- [x] Matches web steps exactly
- [x] Handles same edge cases
- [x] Same backend calls in same order
- [x] Same data persisted
- [x] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled equivalently
- [ ] E2E test exists

### Workflow: Search/filter/sort

- [x] Matches web steps exactly
- [x] Handles same edge cases
- [x] Same backend calls in same order
- [x] Same data persisted
- [x] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled equivalently
- [ ] E2E test exists

### Workflow: Settings/profile/preferences

- [x] Matches web steps exactly
- [x] Handles same edge cases
- [x] Same backend calls in same order
- [x] Same data persisted
- [x] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled equivalently
- [ ] E2E test exists

### Workflow: Connections management

- [x] Matches web steps exactly
- [x] Handles same edge cases
- [x] Same backend calls in same order
- [x] Same data persisted
- [x] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled equivalently
- [ ] E2E test exists

### Workflow: Checkout/payment and billing portal

- [x] Matches web steps exactly (web checkout inside WebView/external)
- [x] Handles same edge cases at web layer
- [x] Same backend calls in same order
- [x] Same data persisted
- [x] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled equivalently
- [ ] E2E test exists

### Workflow: Upload/download (attachments)

- [x] Matches web steps exactly when WebView picker/download works
- [ ] Handles same edge cases on all platforms
- [x] Same backend calls in same order
- [x] Same data persisted
- [ ] Same success/failure user feedback verified on all platforms
- [ ] Offline / flaky network behavior handled equivalently
- [ ] E2E test exists

### Workflow: Voice assistant

- [ ] Matches web steps exactly
- [ ] Handles same edge cases
- [ ] Same backend calls in same order
- [ ] Same data persisted
- [ ] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled equivalently
- [ ] E2E test exists

### Workflow: Push notifications and notification handling

- [ ] Matches web steps exactly
- [ ] Handles same edge cases
- [ ] Same backend calls in same order
- [ ] Same data persisted
- [ ] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled equivalently
- [ ] E2E test exists

### Workflow: Deep linking (auth callback + in-app route open)

- [ ] Matches web steps exactly
- [ ] Handles same edge cases
- [ ] Same backend calls in same order
- [ ] Same data persisted
- [ ] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled equivalently
- [ ] E2E test exists

## E) Integrations Parity Checklist

### Better Auth + OAuth/social login

- [x] Equivalent native implementation exists (provider discovery + sign-in handoff)
- [x] Credentials/env vars configured (where provided)
- [ ] Verified on all platforms
- [x] Data/events match web auth path

### tRPC + API/data model parity

- [x] Equivalent native implementation exists
- [x] Credentials/env vars configured
- [ ] Verified on all platforms
- [x] Data/events match web

### Analytics (PostHog + Dub)

- [x] Equivalent path exists via embedded web app events
- [x] Credentials/env vars configured
- [ ] Verified on all platforms
- [ ] Data/events match web + native shell events (native shell events not mapped)

### Error reporting (Sentry)

- [x] Equivalent path exists via embedded web app Sentry
- [x] Credentials/env vars configured
- [ ] Verified on all platforms
- [ ] Data/events match web + native shell crashes (native RN SDK not integrated)

### Intercom

- [x] Equivalent path exists via embedded web UI integration
- [x] Credentials/env vars configured
- [ ] Verified on all platforms
- [ ] Data/events match web

### Payments/billing (Autumn)

- [x] Equivalent implementation exists via web billing flows
- [x] Credentials/env vars configured
- [ ] Verified on all platforms
- [ ] Data/events match web (native instrumentation missing)

### Voice (ElevenLabs)

- [ ] Equivalent native implementation exists
- [x] Credentials/env vars configured
- [ ] Verified on all platforms
- [ ] Data/events match web

### Push notifications

- [ ] Equivalent native implementation exists
- [ ] Credentials/env vars configured
- [ ] Verified on all platforms
- [ ] Data/events match web

### Maps/location

- [ ] Equivalent native implementation exists
- [ ] Credentials/env vars configured
- [ ] Verified on all platforms
- [ ] Data/events match web

### Camera/photos + file system

- [ ] Equivalent native implementation exists (native modules not yet added)
- [ ] Credentials/env vars configured
- [ ] Verified on all platforms
- [ ] Data/events match web

### Deep linking

- [ ] Equivalent native implementation exists
- [ ] Credentials/env vars configured
- [ ] Verified on all platforms
- [ ] Data/events match web

### Twilio OTP (server-driven)

- [x] Equivalent backend integration exists
- [x] Credentials/env vars configured (if provided)
- [ ] Verified on all platforms
- [ ] Data/events match web

## F) Visual Regression & “99% Same” Proof

- [ ] For every screen: capture reference screenshots on web and each platform
- [ ] Compare and record differences
- [ ] Log acceptable differences with explicit justification
- [x] Maintain `/parity_screenshots/` folder with naming convention

Naming convention:

- `ScreenName__web.png`
- `ScreenName__ios.png`
- `ScreenName__android.png`
- `ScreenName__macos.png`

## G) Acceptance Criteria (Definition of Done)

- [x] 100% of web routes have RN equivalents (or explicit mapping) in this checklist
- [ ] All workflows pass on iOS/Android/macOS
- [ ] No 🔴 items remain
- [ ] Only documented, justified UI differences remain
- [ ] Performance meets baseline (startup, list scroll, nav responsiveness)
- [ ] Release builds succeed on all platforms

## Working Rules

- Update this checklist after every parity PR.
- If a parity gap is found, add/update a task in `TASK.md` and link it here.
- Prefer objective verification: tests + screenshots + measured performance.

## Linked Gap Tasks

See `TASK.md` section: **Parity Gap Tasks (2026-02-21)**

- PARITY-001 Screenshot baseline and visual diff evidence
- PARITY-002 Android compile + smoke matrix
- PARITY-003 iOS compile gate pass with artifact evidence
- PARITY-004 macOS compile gate pass with artifact evidence
- PARITY-005 Deep linking/auth callback parity
- PARITY-006 Native analytics + crash instrumentation parity
- PARITY-007 Accessibility audit pass
- PARITY-008 Performance baseline and thresholds
- PARITY-009 Native voice assistant parity decision and implementation
- PARITY-010 Attachment upload/download native validation

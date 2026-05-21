# PARITY_CHECKLIST.md

Last updated: 2026-03-03

This file is the living single source of truth for Web -> Native parity.
Current active migration scope for this stream is `apps/ios` (web -> iOS parity).

## Feature Parity Inventory

### 1) Web Route/Page Inventory (source: `apps/mail/app/routes.ts`)

| Web Route                        | Purpose                                                                  | Primary Web Entry                                                                      |
| -------------------------------- | ------------------------------------------------------------------------ | -------------------------------------------------------------------------------------- |
| `/`                              | Landing/home with auth redirect for signed-in users                      | `apps/mail/app/page.tsx`                                                               |
| `/home`                          | Public home                                                              | `apps/mail/app/home/page.tsx`                                                          |
| `/api/mailto-handler`            | Parse mailto URL, create draft, redirect to compose                      | `apps/mail/app/mailto-handler.ts`                                                      |
| `/about`                         | Public about page                                                        | `apps/mail/app/(full-width)/about.tsx`                                                 |
| `/terms`                         | Public terms                                                             | `apps/mail/app/(full-width)/terms.tsx`                                                 |
| `/pricing`                       | Public pricing + plan comparison                                         | `apps/mail/app/(full-width)/pricing.tsx`                                               |
| `/privacy`                       | Public privacy policy                                                    | `apps/mail/app/(full-width)/privacy.tsx`                                               |
| `/contributors`                  | Contributors dashboard (GitHub data/charts)                              | `apps/mail/app/(full-width)/contributors.tsx`                                          |
| `/hr`                            | Internal timezone overlap utility                                        | `apps/mail/app/(full-width)/hr.tsx`                                                    |
| `/login`                         | Auth login (Google OAuth primary)                                        | `apps/mail/app/(auth)/todus/login/page.tsx`                                            |
| `/signup`                        | Auth signup (Google OAuth primary)                                       | `apps/mail/app/(auth)/todus/signup/page.tsx`                                           |
| `/developer`                     | Developer resources                                                      | `apps/mail/app/(routes)/developer/page.tsx`                                            |
| `/mail`                          | Redirect to inbox                                                        | `apps/mail/app/(routes)/mail/page.tsx`                                                 |
| `/mail/create`                   | Legacy compose redirect                                                  | `apps/mail/app/(routes)/mail/create/page.tsx`                                          |
| `/mail/compose`                  | Full-screen compose dialog                                               | `apps/mail/app/(routes)/mail/compose/page.tsx`                                         |
| `/mail/under-construction/:path` | Placeholder page                                                         | `apps/mail/app/(routes)/mail/under-construction/[path]/page.tsx`                       |
| `/mail/:folder`                  | Core mailbox shell/list/thread view                                      | `apps/mail/app/(routes)/mail/[folder]/page.tsx` + `apps/mail/components/mail/mail.tsx` |
| `/settings`                      | Redirect to `/settings/general`                                          | `apps/mail/app/(routes)/settings/page.tsx`                                             |
| `/settings/general`              | Language/timezone/default alias/signature/auto-read/undo-send/animations | `apps/mail/app/(routes)/settings/general/page.tsx`                                     |
| `/settings/appearance`           | Theme settings                                                           | `apps/mail/app/(routes)/settings/appearance/page.tsx`                                  |
| `/settings/connections`          | Connected providers CRUD + reconnect + billing gate                      | `apps/mail/app/(routes)/settings/connections/page.tsx`                                 |
| `/settings/labels`               | Label CRUD + color                                                       | `apps/mail/app/(routes)/settings/labels/page.tsx`                                      |
| `/settings/categories`           | Category config + DnD reorder + default rule                             | `apps/mail/app/(routes)/settings/categories/page.tsx`                                  |
| `/settings/notifications`        | Notification settings form                                               | `apps/mail/app/(routes)/settings/notifications/page.tsx`                               |
| `/settings/privacy`              | External images + trusted senders                                        | `apps/mail/app/(routes)/settings/privacy/page.tsx`                                     |
| `/settings/security`             | Security toggles (2FA, login notifications)                              | `apps/mail/app/(routes)/settings/security/page.tsx`                                    |
| `/settings/shortcuts`            | Keyboard shortcut viewer                                                 | `apps/mail/app/(routes)/settings/shortcuts/page.tsx`                                   |
| `/settings/danger-zone`          | Account deletion flow                                                    | `apps/mail/app/(routes)/settings/danger-zone/page.tsx`                                 |
| `/settings/*`                    | Settings fallback resolver                                               | `apps/mail/app/(routes)/settings/[...settings]/page.tsx`                               |
| `/*`                             | Not found                                                                | `apps/mail/app/meta-files/not-found.ts`                                                |

### 2) Native Surface Inventory

#### iOS + Android (single Expo codebase in `apps/ios`)

| Native Route                      | Web Equivalent                       | Status                       |
| --------------------------------- | ------------------------------------ | ---------------------------- |
| `/(public)/index`                 | `/`                                  | Implemented (partial parity) |
| `/(public)/home`                  | `/home`                              | Implemented (partial parity) |
| `/(public)/about`                 | `/about`                             | Implemented (partial parity) |
| `/(public)/terms`                 | `/terms`                             | Implemented (partial parity) |
| `/(public)/privacy`               | `/privacy`                           | Implemented (partial parity) |
| `/(public)/pricing`               | `/pricing`                           | Implemented (partial parity) |
| `/(public)/contributors`          | `/contributors`                      | Implemented (partial parity) |
| `/(public)/hr`                    | `/hr`                                | Implemented (partial parity) |
| `/(public)/developer`             | `/developer`                         | Implemented (partial parity) |
| `/(auth)/login`                   | `/login`                             | Implemented (partial parity) |
| `/(auth)/web-auth`                | OAuth flow helper for `/login`       | Implemented                  |
| `/(app)/(mail)/[folder]`          | `/mail/:folder`                      | Implemented (partial parity) |
| `/(app)/(mail)/thread/[threadId]` | Thread detail inside `/mail/:folder` | Implemented (partial parity) |
| `/compose`                        | `/mail/compose`                      | Implemented (partial parity) |
| `/api/mailto-handler`             | `/api/mailto-handler`                | Implemented (partial parity) |
| `/(app)/assistant`                | AI sidebar assistant                 | Implemented (partial parity) |
| `/search`                         | Search in mail shell                 | Implemented (partial parity) |
| `/(app)/settings/index`           | `/settings`                          | Implemented (partial parity) |
| `/(app)/settings/general`         | `/settings/general`                  | Implemented (partial parity) |
| `/(app)/settings/appearance`      | `/settings/appearance`               | Implemented (partial parity) |
| `/(app)/settings/connections`     | `/settings/connections`              | Implemented (partial parity) |
| `/(app)/settings/labels`          | `/settings/labels`                   | Implemented (partial parity) |
| `/(app)/settings/categories`      | `/settings/categories`               | Implemented (partial parity) |
| `/(app)/settings/notifications`   | `/settings/notifications`            | Implemented (partial parity) |
| `/(app)/settings/privacy`         | `/settings/privacy`                  | Implemented (partial parity) |
| `/(app)/settings/security`        | `/settings/security`                 | Implemented (partial parity) |
| `/(app)/settings/shortcuts`       | `/settings/shortcuts`                | Implemented (partial parity) |
| `/(app)/settings/danger-zone`     | `/settings/danger-zone`              | Implemented (partial parity) |
| `+not-found`                      | `/*`                                 | Partial                      |

#### macOS (`apps/macos`)

| App                           | Architecture                                | Parity implication                                                                                                           |
| ----------------------------- | ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Electron wrapper (`main.mjs`) | Loads deployed web app URL in BrowserWindow | High route coverage via web runtime, but **not React Native parity** and no native component/interaction parity verification |

### 3) Major UI Component Inventory (web)

Core mail + compose

- `components/mail/mail.tsx` (mail shell, panel layout, category filter, sidebar/thread/AI integration)
- `components/mail/mail-list.tsx` (virtualized list, selection, optimistic actions)
- `components/mail/thread-display.tsx` (thread actions, reply modes, notes)
- `components/mail/mail-display.tsx` + `mail-content.tsx` (render email body, attachments, summary)
- `components/create/create-email.tsx` + `email-composer.tsx` (compose, drafts, scheduling, attachments, AI assist)

Settings + account

- `components/settings/settings-card.tsx`
- `components/connection/add.tsx`
- `components/labels/label-dialog.tsx`

Platform shell + UX system

- `components/ui/app-sidebar.tsx`
- `components/context/command-palette-context.tsx`
- `components/ui/ai-sidebar.tsx`
- Shared UI primitives: button/input/select/dialog/switch/tooltip/card/badge/scroll-area

Native component equivalents (current)

- `src/features/mail/MailSidebar.tsx`
- `src/features/mail/ThreadListItem.tsx`
- `src/features/mail/SwipeableThreadRow.tsx`
- `src/features/mail/MessageCard.tsx`
- Route screens in `apps/ios/app/**`

### 4) Critical Workflow Inventory (web baseline)

- Auth: Google sign-in, session bootstrap, logout, redirect guards
- Mail listing by folder with filters + category views
- Thread detail + actions (archive/delete/spam/star/important/read state)
- Compose new mail, reply, reply-all, forward
- Draft creation/restore/update/delete
- Undo-send and scheduled-send
- Search and command palette quick actions
- Labels CRUD and category management
- Connections add/reconnect/remove
- Privacy/security/general/appearance settings persistence
- Account deletion (danger zone)
- AI assistant sidebar + AI compose/search helpers
- Mailto protocol handling to draft compose

### 5) Integration Inventory

Web integrations detected

- Better Auth (email/social), Google OAuth
- tRPC + React Query
- PostHog analytics
- Dub analytics
- Autumn billing/paywall
- Sentry browser monitoring
- Crisp widget
- OpenAI/Perplexity-backed AI features
- ElevenLabs voice tooling

Native integrations detected (apps/ios)

- Better Auth social flow via WebView and bearer extraction
- tRPC + React Query (+ persisted cache)
- PostHog native analytics bootstrap + event capture hooks
- Sentry native crash/error capture bootstrap
- Secure session storage (`expo-secure-store`)
- Haptics (`expo-haptics`)
- HTML rendering via `react-native-webview`

### 6) Environment Variables and Feature Flags Affecting Behavior

Web/env usage

- `VITE_PUBLIC_APP_URL`
- `VITE_PUBLIC_BACKEND_URL`
- `VITE_PUBLIC_APP_NAME`
- `VITE_PUBLIC_POSTHOG_KEY`
- `VITE_PUBLIC_POSTHOG_HOST`
- `VITE_PUBLIC_ELEVENLABS_AGENT_ID`
- `VITE_PUBLIC_IMAGE_PROXY`
- `VITE_PUBLIC_IMAGE_API_URL`
- `REACT_SCAN`

Native/env usage

- `EXPO_PUBLIC_APP_NAME`
- `EXPO_PUBLIC_WEB_URL`
- `EXPO_PUBLIC_BACKEND_URL`
- `EXPO_PUBLIC_AUTH_BYPASS`
- `EXPO_PUBLIC_POSTHOG_KEY`
- `EXPO_PUBLIC_POSTHOG_HOST`
- `EXPO_PUBLIC_SENTRY_DSN`

Shared/server-sensitive envs that impact behavior parity (configured outside client apps)

- Auth/OAuth: `BETTER_AUTH_*`, `GOOGLE_CLIENT_*`
- AI: `OPENAI_*`, `PERPLEXITY_API_KEY`
- Billing: `AUTUMN_SECRET_KEY`
- Messaging/Email infra: `TWILIO_*`, `RESEND_API_KEY`

### 7) iOS ↔ macOS Feature Parity Matrix

Source: 2026-05-17 macOS hardening + iOS parity sweep. Status legend: ✅ at parity • 🟡 partial (works but missing surface or polish) • 🔴 missing.

| Feature | iOS | macOS | Notes |
| --- | --- | --- | --- |
| **Sign in — Apple** | ✅ | ✅ | Both call Better Auth `sign-in/social`. macOS uses native `AppleIDProvider`. |
| **Sign in — Google** | ✅ | ✅ | Both use `ASWebAuthenticationSession` + backend mobile-token redirect. |
| **Sign in — Email OTP** | ✅ | ✅ | OTP digit filter added on macOS this sweep. |
| **Mailbox — folders / secondary folders** | ✅ | ✅ | macOS sidebar restored Meetings entry; folder sync hardened. |
| **Thread — AI summary** | ✅ | ✅ | Both render summary card from `mailAssistant.summarize`. |
| **Thread — smart actions toolbar** | ✅ | ✅ | macOS gained Create Task / Create Event / Generate Reply (inline spinners) this sweep. |
| **Thread — "Remind me" with snooze** | ✅ | ✅ | macOS now schedules via `MacNotificationService.scheduleEmailReminder` with preset + custom date. |
| **Thread — verification code chip** | ✅ | ✅ | macOS regex extraction + one-shot auto-copy added. |
| **Thread — tracking info chip** | ✅ | ✅ | macOS UPS / FedEx / USPS / order-number extraction added. |
| **Compose — from-account selector** | ✅ | ✅ | Both pick connection on send. |
| **Compose — signatures** | ✅ | ✅ | macOS gained per-connection `MacSignatureStore` + Settings card this sweep. |
| **Compose — attachments** | ✅ | ✅ | macOS NSOpenPanel chips + base64 send via `MacDraftService.SendInput.attachments` added. |
| **Compose — rich text (bold/italic/underline)** | ✅ | ✅ | macOS underline button + ⌘B / ⌘I / ⌘U shortcuts added. |
| **Compose — live recipient validation** | ✅ | ✅ | Inline error chips on both. |
| **Drafts — offline queue** | ✅ | ✅ | SwiftData `DraftRecord` + `DraftService` on both. Idempotent flush + 5-min orphan window confirmed on macOS. |
| **Tasks — list view** | ✅ | ✅ | Both share `TaskRecord` SwiftData model. |
| **Tasks — board view** | ✅ | ✅ | Drag-and-drop status update on both. |
| **Tasks — calendar view** | ✅ | ✅ | |
| **Tasks — folders** | ✅ | ✅ | `FolderSyncService` `syncedIds` enforcement landed on macOS. |
| **Tasks — checklist** | ✅ | ✅ | macOS added per-item add / remove / check with live persistence. |
| **Tasks — recurrence** | ✅ | ✅ | macOS added None / Daily / Weekly / Monthly / Yearly RRULE-compatible recurrence. |
| **Tasks — attachments** | ✅ | ✅ | macOS NSOpenPanel + copy to `Application Support/TaskAttachments/{taskId}/` added. |
| **Tasks — Apple Reminders sync** | ✅ | ✅ | macOS dedup + `@MainActor` isolation hardened. |
| **Calendar — day view** | ✅ | ✅ | |
| **Calendar — week view** | ✅ | ✅ | |
| **Calendar — month view** | ✅ | ✅ | macOS uses paged month stack; gestures tuned. |
| **Calendar — year view** | ✅ | ✅ | macOS year scroll + month red-dot indicator. |
| **Calendar — source picker** | ✅ | ✅ | Multi-calendar toggle on both. |
| **Calendar — in-app create / edit / delete** | ✅ | ✅ | macOS gained native `MacEventEditSheet` this sweep (replaced Calendar.app delegation). |
| **Home — briefing** | ✅ | ✅ | macOS briefing tap → thread deep link added. |
| **Home — setup checklist** | ✅ | ✅ | |
| **Notifications — categories registered** | ✅ | ✅ | macOS `TASK_REMINDER`, `EMAIL`, `EMAIL_REMINDER`, `DUE_TASKS`, `AI_RESPONSE` registered. |
| **Notifications — actions** | ✅ | ✅ | macOS `TASK_COMPLETE`, `TASK_SNOOZE`, `ARCHIVE_EMAIL` wired. |
| **Notifications — foreground (`willPresent`) banners** | ✅ | ✅ | macOS `MacAppDelegate` implements `UNUserNotificationCenterDelegate` (was previously silent in foreground). |
| **Notifications — tap routing** | ✅ | ✅ | macOS `didReceive` routes `taskDue → tasks`, `importantEmail → thread`, `event → calendar`, AI / OTP routes. |
| **Search — cross-entity (tasks + emails + events + people)** | ✅ | ✅ | macOS gained `MacSearchView` with category chips, recent searches, debounced 60-day calendar search, keyboard nav. |
| **Sharing — outbound share link** | ✅ | ✅ | `shareService.createShare` on both. |
| **Sharing — inbound deep link (`todus://share?slug=...`)** | ✅ | ✅ | macOS handler + new `MacSharedConversationView` sheet added this sweep. |
| **Sharing — system share sheet** | ✅ (UIActivity) | 🟡 | macOS uses `NSSharingServicePicker` in most places; not yet wired into every conversation/doc surface. |
| **AI chat — streaming SSE** | ✅ | ✅ | `cancelStream` race fixed on macOS via generation counter. |
| **AI chat — tool calls** | ✅ | ✅ | macOS exec cancellation gates added. |
| **AI chat — share conversation** | ✅ | ✅ | |
| **AI chat — group chat** | ✅ | 🟡 | macOS `GroupChatService` still polls; WebSocket DO subscription migration TODO. |
| **Voice — live chat (Gemini Live)** | ✅ | ✅ | macOS serialized audio send queue with backpressure + `AudioPlayer` derived state. |
| **Voice — push-to-talk global hotkey** | 🔴 | ✅ | macOS `⌘⇧Space` via Carbon `RegisterEventHotKey`. iOS equivalent (Siri Shortcut / AppIntent) tracked in iOS sprint. |
| **Voice — wake word ("Hey Todus" / "computer")** | 🔴 | 🟡 | macOS stub fail-soft; Picovoice Porcupine integration deferred to Phase 1.5 on both platforms. |
| **Docs — web shim editor** | ✅ | ✅ | Both render Tiptap. |
| **Docs — native shell (workspace + CRUD + search)** | 🟡 | ✅ | macOS has full `MacDocsShellView`; iOS still only `DocsWebView` (tracked in iOS sprint). |
| **Docs — autosave + 3-state save indicator** | 🟡 | ✅ | macOS landed this sweep; iOS still single-state. |
| **Meetings** | ✅ | ✅ | macOS sidebar entry restored. |
| **Widgets — home-screen widgets** | ✅ | 🟡 | macOS widget extension wired in `project.yml` but `MacWidgetUpdateManager` real-data hydration verification pass pending. |
| **Settings — general / appearance / connections / labels / categories / notifications / privacy / security / shortcuts / danger-zone** | ✅ | ✅ | Both at parity; macOS settings full-shape save fixed. |
| **Settings — email automation policy (excluded senders, auto-send)** | 🔴 | ✅ | iOS-side tracked in iOS sprint. |
| **Local AI models (Ollama selector)** | ✅ | ✅ | macOS Local Models button-wrapped rows + accessibility labels added. |
| **Sidebar / menu / keyboard shortcuts** | n/a (tab bar) | ✅ | macOS shortcuts: ⌘1–4 calendar modes, ⌘B / ⌘I / ⌘U compose, ⌘1–5 / ⌘↩ in search. |

**Net status (2026-05-17)** — macOS is now at structural parity with iOS for all primary surfaces. The only macOS surfaces still 🟡 vs iOS are: (a) `GroupChatService` polling vs WebSocket DO subscription, (b) widget real-data verification pass, (c) system-share sheet coverage on conversation / doc surfaces. Conversely iOS still trails macOS on: (a) Docs native shell, (b) email automation policy controls, (c) voice push-to-talk hotkey equivalent (AppIntent / Siri Shortcut), (d) Docs autosave 3-state indicator — all tracked under **Current iOS Parity + Hardening Sprint (2026-05-17)** in `TASK.md`. Wake word remains 🔴/🟡 on both pending Phase 1.5 Porcupine integration.

## A) Parity Dashboard

### Status Summary

| Category     | ✅ Complete | 🟡 Partial | 🔴 Missing | ⚠️ Blocked |
| ------------ | ----------: | ---------: | ---------: | ---------: |
| Screens      |           0 |         13 |         17 |          0 |
| Components   |           0 |          7 |         13 |          0 |
| Workflows    |           0 |          6 |          7 |          1 |
| Integrations |           0 |          6 |          9 |          0 |

### Blockers

- No active blockers in current iOS parity scope.

### Gap Tracking Link

- Open parity gap tasks: [TASK.md](./TASK.md) -> section `Parity Gap Tasks (2026-03-01)`

## B) Screen-by-Screen Parity Checklist

### Screen: `/` -> RN: `/(public)/index`

**Status:** 🟡
**Platforms:** iOS implemented via native WebView wrapper / Android same code path (needs validation) / macOS rendered only via Electron web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [x] Data loaded matches web (same API endpoints/queries, same params)
- [x] Loading states match web (skeletons/spinners, placement)
- [ ] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/home` -> RN: `/(public)/home`

**Status:** 🟡
**Platforms:** iOS implemented via native WebView wrapper / Android same code path (needs validation) / macOS rendered only via Electron web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [x] Data loaded matches web (same API endpoints/queries, same params)
- [x] Loading states match web (skeletons/spinners, placement)
- [ ] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/login` -> RN: `/(auth)/login` + `/(auth)/web-auth`

**Status:** 🟡
**Platforms:** iOS implemented / Android same code path (needs validation) / macOS currently web wrapper login

Checklist:

- [x] Layout matches web (spacing, alignment, breakpoints equivalents)
- [x] Typography matches web (font family, size scale, weights, line height)
- [x] Colors match web (tokens, gradients, borders, shadows)
- [x] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [x] Data loaded matches web (same API endpoints/queries, same params)
- [x] Loading states match web (skeletons/spinners, placement)
- [ ] Empty states match web (copy, visuals, actions)
- [x] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/signup` -> RN: Missing

**Status:** 🔴
**Platforms:** iOS missing / Android missing / macOS rendered only via Electron web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [ ] Navigation matches (entry points, back behavior, deep links if any)
- [ ] Data loaded matches web (same API endpoints/queries, same params)
- [ ] Loading states match web (skeletons/spinners, placement)
- [ ] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/about` -> RN: `/(public)/about`

**Status:** 🟡
**Platforms:** iOS implemented via native WebView wrapper / Android same code path (needs validation) / macOS rendered only via Electron web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [x] Data loaded matches web (same API endpoints/queries, same params)
- [x] Loading states match web (skeletons/spinners, placement)
- [ ] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/terms` -> RN: `/(public)/terms`

**Status:** 🟡
**Platforms:** iOS implemented via native WebView wrapper / Android same code path (needs validation) / macOS rendered only via Electron web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [x] Data loaded matches web (same API endpoints/queries, same params)
- [x] Loading states match web (skeletons/spinners, placement)
- [ ] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/pricing` -> RN: `/(public)/pricing`

**Status:** 🟡
**Platforms:** iOS implemented via native WebView wrapper / Android same code path (needs validation) / macOS rendered only via Electron web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [x] Data loaded matches web (same API endpoints/queries, same params)
- [x] Loading states match web (skeletons/spinners, placement)
- [ ] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/privacy` -> RN: `/(public)/privacy`

**Status:** 🟡
**Platforms:** iOS implemented via native WebView wrapper / Android same code path (needs validation) / macOS rendered only via Electron web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [x] Data loaded matches web (same API endpoints/queries, same params)
- [x] Loading states match web (skeletons/spinners, placement)
- [ ] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/contributors` -> RN: `/(public)/contributors`

**Status:** 🟡
**Platforms:** iOS implemented via native WebView wrapper / Android same code path (needs validation) / macOS rendered only via Electron web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [x] Data loaded matches web (same API endpoints/queries, same params)
- [x] Loading states match web (skeletons/spinners, placement)
- [ ] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/hr` -> RN: `/(public)/hr`

**Status:** 🟡
**Platforms:** iOS implemented via native WebView wrapper / Android same code path (needs validation) / macOS rendered only via Electron web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [x] Data loaded matches web (same API endpoints/queries, same params)
- [x] Loading states match web (skeletons/spinners, placement)
- [ ] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/developer` -> RN: `/(public)/developer`

**Status:** 🟡
**Platforms:** iOS implemented via native WebView wrapper / Android same code path (needs validation) / macOS rendered only via Electron web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [x] Data loaded matches web (same API endpoints/queries, same params)
- [x] Loading states match web (skeletons/spinners, placement)
- [ ] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/mail` -> RN: `/(app)/(mail)/inbox` via auth guard redirect

**Status:** 🟡
**Platforms:** iOS implemented / Android same code path (needs validation) / macOS route available via web wrapper

Checklist:

- [x] Layout matches web (spacing, alignment, breakpoints equivalents)
- [x] Typography matches web (font family, size scale, weights, line height)
- [x] Colors match web (tokens, gradients, borders, shadows)
- [x] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [x] Data loaded matches web (same API endpoints/queries, same params)
- [x] Loading states match web (skeletons/spinners, placement)
- [x] Empty states match web (copy, visuals, actions)
- [x] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/mail/:folder` -> RN: `/(app)/(mail)/[folder]`

**Status:** 🟡
**Platforms:** iOS implemented / Android same code path (needs validation) / macOS route available via web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [x] Data loaded matches web (same API endpoints/queries, same params)
- [x] Loading states match web (skeletons/spinners, placement)
- [x] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/mail/compose` -> RN: `/compose`

**Status:** 🟡
**Platforms:** iOS implemented / Android same code path (needs validation) / macOS route available via web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [x] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [x] Data loaded matches web (same API endpoints/queries, same params)
- [x] Loading states match web (skeletons/spinners, placement)
- [x] Empty states match web (copy, visuals, actions)
- [x] Error states match web (messages, retry flows)
- [x] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [x] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `AI assistant sidebar` -> RN: `/(app)/assistant`

**Status:** 🟡
**Platforms:** iOS implemented / Android same code path (needs validation) / macOS route handled only in web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [x] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [x] Data loaded matches web (same API endpoints/queries, same params)
- [x] Loading states match web (skeletons/spinners, placement)
- [x] Empty states match web (copy, visuals, actions)
- [x] Error states match web (messages, retry flows)
- [x] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [x] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/mail/create` -> RN: `/compose` (alias behavior)

**Status:** 🟡
**Platforms:** iOS mapped to `/compose` / Android same code path (needs validation) / macOS route handled only in web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [x] Data loaded matches web (same API endpoints/queries, same params)
- [ ] Loading states match web (skeletons/spinners, placement)
- [ ] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/mail/under-construction/:path` -> RN: `/(app)/(mail)/under-construction/[path]`

**Status:** 🟡
**Platforms:** iOS implemented / Android same code path (needs validation) / macOS route handled only in web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [x] Data loaded matches web (same API endpoints/queries, same params)
- [x] Loading states match web (skeletons/spinners, placement)
- [x] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/settings` -> RN: `/(app)/settings/index`

**Status:** 🟡
**Platforms:** iOS implemented / Android same code path (needs validation) / macOS route available via web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [x] Data loaded matches web (same API endpoints/queries, same params)
- [ ] Loading states match web (skeletons/spinners, placement)
- [ ] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/settings/general` -> RN: `/(app)/settings/general`

**Status:** 🟡
**Platforms:** iOS placeholder screen / Android same code path (needs validation) / macOS route available via web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [ ] Data loaded matches web (same API endpoints/queries, same params)
- [ ] Loading states match web (skeletons/spinners, placement)
- [ ] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/settings/appearance` -> RN: `/(app)/settings/appearance`

**Status:** 🟡
**Platforms:** iOS implemented (no persistence yet) / Android same code path (needs validation) / macOS route available via web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [ ] Data loaded matches web (same API endpoints/queries, same params)
- [ ] Loading states match web (skeletons/spinners, placement)
- [ ] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/settings/connections` -> RN: `/(app)/settings/connections`

**Status:** 🟡
**Platforms:** iOS list view implemented / Android same code path (needs validation) / macOS route available via web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [x] Data loaded matches web (same API endpoints/queries, same params)
- [ ] Loading states match web (skeletons/spinners, placement)
- [x] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/settings/labels` -> RN: `/(app)/settings/labels`

**Status:** 🟡
**Platforms:** iOS list view implemented / Android same code path (needs validation) / macOS route available via web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [x] Data loaded matches web (same API endpoints/queries, same params)
- [ ] Loading states match web (skeletons/spinners, placement)
- [x] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/settings/categories` -> RN: `/(app)/settings/categories`

**Status:** 🟡
**Platforms:** iOS implemented / Android same code path (needs validation) / macOS route handled only in web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [ ] Navigation matches (entry points, back behavior, deep links if any)
- [ ] Data loaded matches web (same API endpoints/queries, same params)
- [ ] Loading states match web (skeletons/spinners, placement)
- [ ] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/settings/notifications` -> RN: `/(app)/settings/notifications`

**Status:** 🟡
**Platforms:** iOS implemented / Android same code path (needs validation) / macOS route handled only in web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [ ] Navigation matches (entry points, back behavior, deep links if any)
- [ ] Data loaded matches web (same API endpoints/queries, same params)
- [ ] Loading states match web (skeletons/spinners, placement)
- [ ] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/settings/privacy` -> RN: `/(app)/settings/privacy`

**Status:** 🟡
**Platforms:** iOS implemented / Android same code path (needs validation) / macOS route handled only in web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [ ] Navigation matches (entry points, back behavior, deep links if any)
- [ ] Data loaded matches web (same API endpoints/queries, same params)
- [ ] Loading states match web (skeletons/spinners, placement)
- [ ] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/settings/security` -> RN: `/(app)/settings/security`

**Status:** 🟡
**Platforms:** iOS implemented / Android same code path (needs validation) / macOS route handled only in web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [ ] Navigation matches (entry points, back behavior, deep links if any)
- [ ] Data loaded matches web (same API endpoints/queries, same params)
- [ ] Loading states match web (skeletons/spinners, placement)
- [ ] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/settings/shortcuts` -> RN: `/(app)/settings/shortcuts`

**Status:** 🟡
**Platforms:** iOS implemented / Android same code path (needs validation) / macOS route handled only in web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [ ] Navigation matches (entry points, back behavior, deep links if any)
- [ ] Data loaded matches web (same API endpoints/queries, same params)
- [ ] Loading states match web (skeletons/spinners, placement)
- [ ] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/settings/danger-zone` -> RN: `/(app)/settings/danger-zone`

**Status:** 🟡
**Platforms:** iOS implemented / Android same code path (needs validation) / macOS route handled only in web wrapper

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [ ] Navigation matches (entry points, back behavior, deep links if any)
- [ ] Data loaded matches web (same API endpoints/queries, same params)
- [ ] Loading states match web (skeletons/spinners, placement)
- [ ] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/settings/*` -> RN: Partial fallback (`+not-found` + settings index)

**Status:** 🟡
**Platforms:** iOS partial / Android same code path (needs validation) / macOS web wrapper fallback

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [ ] Data loaded matches web (same API endpoints/queries, same params)
- [ ] Loading states match web (skeletons/spinners, placement)
- [x] Empty states match web (copy, visuals, actions)
- [x] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/*` -> RN: `+not-found`

**Status:** 🟡
**Platforms:** iOS implemented / Android same code path (needs validation) / macOS web wrapper has web 404

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [x] Data loaded matches web (same API endpoints/queries, same params)
- [x] Loading states match web (skeletons/spinners, placement)
- [x] Empty states match web (copy, visuals, actions)
- [x] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/api/mailto-handler` -> RN: `/api/mailto-handler`

**Status:** 🟡
**Platforms:** iOS implemented / Android same code path (needs validation) / macOS handled by web wrapper path only

Checklist:

- [ ] Layout matches web (spacing, alignment, breakpoints equivalents)
- [ ] Typography matches web (font family, size scale, weights, line height)
- [ ] Colors match web (tokens, gradients, borders, shadows)
- [ ] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [x] Data loaded matches web (same API endpoints/queries, same params)
- [x] Loading states match web (skeletons/spinners, placement)
- [ ] Empty states match web (copy, visuals, actions)
- [ ] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

## C) Component Parity Checklist

Component: `AppSidebar` -> RN: `MailSidebar`

- [ ] Props parity (same behaviors, defaults)
- [ ] Visual parity (dimensions, typography, colors)
- [ ] Interaction parity (hover -> native equivalent, press states)
- [ ] Disabled/loading states parity
- [ ] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors

Component: `MailList` -> RN: `FlashList` + `ThreadListItem`

- [ ] Props parity (same behaviors, defaults)
- [ ] Visual parity (dimensions, typography, colors)
- [ ] Interaction parity (hover -> native equivalent, press states)
- [x] Disabled/loading states parity
- [ ] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors

Component: `ThreadDisplay` -> RN: `thread/[threadId].tsx`

- [ ] Props parity (same behaviors, defaults)
- [ ] Visual parity (dimensions, typography, colors)
- [ ] Interaction parity (hover -> native equivalent, press states)
- [ ] Disabled/loading states parity
- [ ] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors

Component: `MailDisplay` + `MailContent` -> RN: `MessageCard`

- [ ] Props parity (same behaviors, defaults)
- [ ] Visual parity (dimensions, typography, colors)
- [ ] Interaction parity (hover -> native equivalent, press states)
- [x] Disabled/loading states parity
- [ ] Error/validation display parity
- [ ] Theming/token usage parity
- [ ] Unit tests for core behaviors

Component: `CreateEmail` + `EmailComposer` -> RN: `compose.tsx`

- [ ] Props parity (same behaviors, defaults)
- [ ] Visual parity (dimensions, typography, colors)
- [ ] Interaction parity (hover -> native equivalent, press states)
- [x] Disabled/loading states parity
- [ ] Error/validation display parity
- [x] Theming/token usage parity
- [x] Unit tests for core behaviors

Component: `ReplyCompose` -> RN: `compose.tsx` reply mode

- [ ] Props parity (same behaviors, defaults)
- [ ] Visual parity (dimensions, typography, colors)
- [ ] Interaction parity (hover -> native equivalent, press states)
- [x] Disabled/loading states parity
- [ ] Error/validation display parity
- [x] Theming/token usage parity
- [x] Unit tests for core behaviors

Component: `SettingsCard` -> RN: settings section cards (`settings/*.tsx`)

- [ ] Props parity (same behaviors, defaults)
- [ ] Visual parity (dimensions, typography, colors)
- [ ] Interaction parity (hover -> native equivalent, press states)
- [ ] Disabled/loading states parity
- [ ] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors

Component: `AddConnectionDialog` -> RN: missing

- [ ] Props parity (same behaviors, defaults)
- [ ] Visual parity (dimensions, typography, colors)
- [ ] Interaction parity (hover -> native equivalent, press states)
- [ ] Disabled/loading states parity
- [ ] Error/validation display parity
- [ ] Theming/token usage parity
- [ ] Unit tests for core behaviors

Component: `LabelDialog` -> RN: missing

- [ ] Props parity (same behaviors, defaults)
- [ ] Visual parity (dimensions, typography, colors)
- [ ] Interaction parity (hover -> native equivalent, press states)
- [ ] Disabled/loading states parity
- [ ] Error/validation display parity
- [ ] Theming/token usage parity
- [ ] Unit tests for core behaviors

Component: `CategoryDropdown` / category management -> RN: missing

- [ ] Props parity (same behaviors, defaults)
- [ ] Visual parity (dimensions, typography, colors)
- [ ] Interaction parity (hover -> native equivalent, press states)
- [ ] Disabled/loading states parity
- [ ] Error/validation display parity
- [ ] Theming/token usage parity
- [ ] Unit tests for core behaviors

Component: `CommandPaletteProvider` -> RN: missing

- [ ] Props parity (same behaviors, defaults)
- [ ] Visual parity (dimensions, typography, colors)
- [ ] Interaction parity (hover -> native equivalent, press states)
- [ ] Disabled/loading states parity
- [ ] Error/validation display parity
- [ ] Theming/token usage parity
- [ ] Unit tests for core behaviors

Component: `AISidebar` -> RN: `/(app)/assistant`

- [x] Props parity (same behaviors, defaults)
- [ ] Visual parity (dimensions, typography, colors)
- [x] Interaction parity (hover -> native equivalent, press states)
- [x] Disabled/loading states parity
- [x] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors

Component: `NotesPanel` -> RN: `ThreadDetailPane` notes section

- [x] Props parity (same behaviors, defaults)
- [ ] Visual parity (dimensions, typography, colors)
- [x] Interaction parity (hover -> native equivalent, press states)
- [x] Disabled/loading states parity
- [x] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors

Component: `ThreadContextMenu` bulk actions -> RN: partial (`SwipeableThreadRow` + header actions)

- [ ] Props parity (same behaviors, defaults)
- [ ] Visual parity (dimensions, typography, colors)
- [x] Interaction parity (hover -> native equivalent, press states)
- [x] Disabled/loading states parity
- [ ] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors

## D) Workflow Parity Checklist (End-to-End)

Workflow: Auth signup/login/logout/reset password/session refresh

- [ ] Matches web steps exactly
- [ ] Handles same edge cases
- [ ] Same backend calls in same order
- [ ] Same data persisted (and cleared) as web
- [ ] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled (if web handles it)
- [ ] E2E test exists (or manual test script documented)

Workflow: Browse folder -> open thread -> archive/delete/spam/star/mark-read

- [x] Matches web steps exactly
- [ ] Handles same edge cases
- [x] Same backend calls in same order
- [ ] Same data persisted (and cleared) as web
- [ ] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled (if web handles it)
- [ ] E2E test exists (or manual test script documented)

Workflow: Compose new email

- [x] Matches web steps exactly
- [x] Handles same edge cases
- [x] Same backend calls in same order
- [x] Same data persisted (and cleared) as web
- [x] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled (if web handles it)
- [ ] E2E test exists (or manual test script documented)

Workflow: Reply / reply-all / forward

- [x] Matches web steps exactly
- [x] Handles same edge cases
- [x] Same backend calls in same order
- [x] Same data persisted (and cleared) as web
- [x] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled (if web handles it)
- [ ] E2E test exists (or manual test script documented)

Workflow: Draft autosave/restore/delete

- [x] Matches web steps exactly
- [x] Handles same edge cases
- [x] Same backend calls in same order
- [x] Same data persisted (and cleared) as web
- [x] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled (if web handles it)
- [ ] E2E test exists (or manual test script documented)

Workflow: Search/filter/sort flows

- [ ] Matches web steps exactly
- [ ] Handles same edge cases
- [ ] Same backend calls in same order
- [ ] Same data persisted (and cleared) as web
- [ ] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled (if web handles it)
- [ ] E2E test exists (or manual test script documented)

Workflow: Settings/profile flows

- [ ] Matches web steps exactly
- [ ] Handles same edge cases
- [ ] Same backend calls in same order
- [ ] Same data persisted (and cleared) as web
- [ ] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled (if web handles it)
- [ ] E2E test exists (or manual test script documented)

Workflow: Connections management (add/remove/reconnect)

- [ ] Matches web steps exactly
- [ ] Handles same edge cases
- [ ] Same backend calls in same order
- [ ] Same data persisted (and cleared) as web
- [ ] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled (if web handles it)
- [ ] E2E test exists (or manual test script documented)

Workflow: Labels/categories CRUD and assignment

- [ ] Matches web steps exactly
- [ ] Handles same edge cases
- [ ] Same backend calls in same order
- [ ] Same data persisted (and cleared) as web
- [ ] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled (if web handles it)
- [ ] E2E test exists (or manual test script documented)

Workflow: AI assistant + compose helpers

- [ ] Matches web steps exactly
- [ ] Handles same edge cases
- [x] Same backend calls in same order
- [ ] Same data persisted (and cleared) as web
- [x] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled (if web handles it)
- [ ] E2E test exists (or manual test script documented)

Workflow: Mailto URL -> draft -> compose

- [x] Matches web steps exactly
- [ ] Handles same edge cases
- [x] Same backend calls in same order
- [x] Same data persisted (and cleared) as web
- [x] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled (if web handles it)
- [ ] E2E test exists (or manual test script documented)

Workflow: macOS native parity workflow verification

- [ ] Matches web steps exactly
- [ ] Handles same edge cases
- [ ] Same backend calls in same order
- [ ] Same data persisted (and cleared) as web
- [ ] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled (if web handles it)
- [ ] E2E test exists (or manual test script documented)
- [ ] Blocked reason resolved (currently Electron wrapper, no RN macOS implementation)

## E) Integrations Parity Checklist

Integration: Better Auth + Google OAuth

- [x] Equivalent native implementation exists
- [x] Credentials/env vars configured
- [ ] Verified on all platforms
- [ ] Data/events match web

Integration: tRPC + React Query data layer

- [x] Equivalent native implementation exists
- [x] Credentials/env vars configured
- [ ] Verified on all platforms
- [ ] Data/events match web

Integration: Analytics (PostHog)

- [x] Equivalent native implementation exists
- [x] Credentials/env vars configured
- [ ] Verified on all platforms
- [x] Data/events match web

Integration: Dub analytics

- [ ] Equivalent native implementation exists
- [ ] Credentials/env vars configured
- [ ] Verified on all platforms
- [ ] Data/events match web

Integration: Error reporting (Sentry)

- [x] Equivalent native implementation exists
- [x] Credentials/env vars configured
- [ ] Verified on all platforms
- [x] Data/events match web

Integration: Billing/payments (Autumn)

- [ ] Equivalent native implementation exists
- [ ] Credentials/env vars configured
- [ ] Verified on all platforms
- [ ] Data/events match web

Integration: Voice (ElevenLabs) — ⚠️ Blocked (web implementation depends on browser-only `@elevenlabs/react`)

- [ ] Equivalent native implementation exists
- [ ] Credentials/env vars configured
- [ ] Verified on all platforms
- [ ] Data/events match web

Integration: AI helpers (OpenAI/Perplexity-backed features)

- [x] Equivalent native implementation exists
- [x] Credentials/env vars configured
- [ ] Verified on all platforms
- [x] Data/events match web

Integration: Deep linking + mailto handling

- [x] Equivalent native implementation exists
- [x] Credentials/env vars configured
- [ ] Verified on all platforms
- [x] Data/events match web

Integration: OAuth/social login

- [x] Equivalent native implementation exists
- [x] Credentials/env vars configured
- [ ] Verified on all platforms
- [ ] Data/events match web

Integration: Push notifications

- [ ] Equivalent native implementation exists
- [ ] Credentials/env vars configured
- [ ] Verified on all platforms
- [ ] Data/events match web

Integration: Maps/location

- [ ] Equivalent native implementation exists
- [ ] Credentials/env vars configured
- [ ] Verified on all platforms
- [ ] Data/events match web

Integration: Camera/photos

- [ ] Equivalent native implementation exists
- [ ] Credentials/env vars configured
- [ ] Verified on all platforms
- [ ] Data/events match web

Integration: File system / attachment picker

- [ ] Equivalent native implementation exists
- [ ] Credentials/env vars configured
- [ ] Verified on all platforms
- [ ] Data/events match web

Integration: Crisp chat

- [ ] Equivalent native implementation exists
- [ ] Credentials/env vars configured
- [ ] Verified on all platforms
- [ ] Data/events match web

## F) Visual Regression and 99% Same Proof

Required procedure

- [ ] For every screen: capture reference screenshots on web and each platform
- [ ] Compare and record differences
- [ ] Log acceptable differences (for example native switch styling) with justification
- [x] Maintain a `/parity_screenshots/` folder with naming convention:
      `ScreenName__web.png`, `ScreenName__ios.png`, `ScreenName__android.png`, `ScreenName__macos.png`

Current implementation artifacts

- `/parity_screenshots/manifest.json` (required screen inventory + platform matrix)
- `/parity_screenshots/SCREENSHOT_LOG.md` (per-screen diff notes + acceptance tracking)
- `pnpm parity:screenshots:check` (coverage verifier script)

Acceptance notes for visual diffs

- Keep a per-screen diff log with pixel/spacing/typography variances and rationale.
- Any unresolved variance blocks `✅ Complete` status.

## G) Acceptance Criteria (Definition of Done)

App is parity complete only when:

- [ ] 100% of web routes have RN equivalents (or explicitly deprecated with approval)
- [ ] All workflows pass on iOS/Android/macOS
- [ ] No 🔴 items remain
- [ ] Only documented, justified UI differences remain
- [ ] Performance meets baseline (startup time, list scrolling, navigation responsiveness)
- [ ] Release builds succeed on all platforms

## Working Rules

- This checklist is a living artifact and must be updated after every migration PR.
- Every newly discovered parity gap must be tracked in [TASK.md](./TASK.md) under `Parity Gap Tasks (2026-03-01)`.
- Prefer objective verification (tests + screenshots) over subjective parity claims.

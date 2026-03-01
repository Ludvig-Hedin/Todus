# PARITY_CHECKLIST.md

Last updated: 2026-03-01

This file is the living single source of truth for Web -> Native parity across iOS, Android, and macOS.

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
| `/(auth)/login`                   | `/login`                             | Implemented (partial parity) |
| `/(auth)/web-auth`                | OAuth flow helper for `/login`       | Implemented                  |
| `/(app)/(mail)/[folder]`          | `/mail/:folder`                      | Implemented (partial parity) |
| `/(app)/(mail)/thread/[threadId]` | Thread detail inside `/mail/:folder` | Implemented (partial parity) |
| `/compose`                        | `/mail/compose`                      | Implemented (partial parity) |
| `/search`                         | Search in mail shell                 | Implemented (partial parity) |
| `/(app)/settings/index`           | `/settings`                          | Implemented (partial parity) |
| `/(app)/settings/general`         | `/settings/general`                  | Placeholder only             |
| `/(app)/settings/appearance`      | `/settings/appearance`               | Partial                      |
| `/(app)/settings/connections`     | `/settings/connections`              | Partial                      |
| `/(app)/settings/labels`          | `/settings/labels`                   | Partial                      |
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

## A) Parity Dashboard

### Status Summary

| Category     | ✅ Complete | 🟡 Partial | 🔴 Missing | ⚠️ Blocked |
| ------------ | ----------: | ---------: | ---------: | ---------: |
| Screens      |           0 |         11 |         19 |          0 |
| Components   |           0 |          7 |         13 |          0 |
| Workflows    |           0 |          5 |          8 |          1 |
| Integrations |           0 |          5 |         10 |          0 |

### Blockers

- ⚠️ macOS app is currently an Electron web wrapper (`apps/macos`), not a React Native macOS app.
- ⚠️ Cross-platform screenshot capture/compare still requires simulator/device runs and authenticated parity accounts.

### Gap Tracking Link

- Open parity gap tasks: [TASK.md](./TASK.md) -> section `Parity Gap Tasks (2026-03-01)`

## B) Screen-by-Screen Parity Checklist

### Screen: `/` -> RN: Missing

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

### Screen: `/home` -> RN: Missing

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

### Screen: `/about` -> RN: Missing

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

### Screen: `/terms` -> RN: Missing

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

### Screen: `/pricing` -> RN: Missing

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

### Screen: `/privacy` -> RN: Missing

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

### Screen: `/contributors` -> RN: Missing

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

### Screen: `/hr` -> RN: Missing

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

### Screen: `/developer` -> RN: Missing

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
- [ ] Components match web (inputs, buttons, cards, modals)
- [x] Navigation matches (entry points, back behavior, deep links if any)
- [x] Data loaded matches web (same API endpoints/queries, same params)
- [ ] Loading states match web (skeletons/spinners, placement)
- [ ] Empty states match web (copy, visuals, actions)
- [x] Error states match web (messages, retry flows)
- [ ] Forms match web (validation rules, masking, keyboard behavior)
- [ ] Accessibility parity (labels, focus order, dynamic type support where applicable)
- [ ] Performance acceptable (no jank on scroll, avoids excessive re-renders)
- [ ] Analytics events parity (same names/properties if used)
- [ ] Screenshots captured (web vs iOS vs Android vs macOS)

### Screen: `/mail/create` -> RN: Missing

**Status:** 🔴
**Platforms:** iOS missing / Android missing / macOS route handled only in web wrapper

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

### Screen: `/mail/under-construction/:path` -> RN: Missing

**Status:** 🔴
**Platforms:** iOS missing / Android missing / macOS route handled only in web wrapper

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

### Screen: `/settings/categories` -> RN: Missing

**Status:** 🔴
**Platforms:** iOS missing / Android missing / macOS route handled only in web wrapper

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

### Screen: `/settings/notifications` -> RN: Missing

**Status:** 🔴
**Platforms:** iOS missing / Android missing / macOS route handled only in web wrapper

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

### Screen: `/settings/privacy` -> RN: Missing

**Status:** 🔴
**Platforms:** iOS missing / Android missing / macOS route handled only in web wrapper

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

### Screen: `/settings/security` -> RN: Missing

**Status:** 🔴
**Platforms:** iOS missing / Android missing / macOS route handled only in web wrapper

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

### Screen: `/settings/shortcuts` -> RN: Missing

**Status:** 🔴
**Platforms:** iOS missing / Android missing / macOS route handled only in web wrapper

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

### Screen: `/settings/danger-zone` -> RN: Missing

**Status:** 🔴
**Platforms:** iOS missing / Android missing / macOS route handled only in web wrapper

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

### Screen: `/api/mailto-handler` -> RN: Missing (no native mailto parser/create-draft bridge)

**Status:** 🔴
**Platforms:** iOS missing / Android missing / macOS handled by web wrapper path only

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
- [ ] Unit tests for core behaviors

Component: `ReplyCompose` -> RN: `compose.tsx` reply mode

- [ ] Props parity (same behaviors, defaults)
- [ ] Visual parity (dimensions, typography, colors)
- [ ] Interaction parity (hover -> native equivalent, press states)
- [x] Disabled/loading states parity
- [ ] Error/validation display parity
- [x] Theming/token usage parity
- [ ] Unit tests for core behaviors

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

Component: `AISidebar` -> RN: missing

- [ ] Props parity (same behaviors, defaults)
- [ ] Visual parity (dimensions, typography, colors)
- [ ] Interaction parity (hover -> native equivalent, press states)
- [ ] Disabled/loading states parity
- [ ] Error/validation display parity
- [ ] Theming/token usage parity
- [ ] Unit tests for core behaviors

Component: `NotesPanel` -> RN: missing

- [ ] Props parity (same behaviors, defaults)
- [ ] Visual parity (dimensions, typography, colors)
- [ ] Interaction parity (hover -> native equivalent, press states)
- [ ] Disabled/loading states parity
- [ ] Error/validation display parity
- [ ] Theming/token usage parity
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

- [ ] Matches web steps exactly
- [ ] Handles same edge cases
- [ ] Same backend calls in same order
- [ ] Same data persisted (and cleared) as web
- [ ] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled (if web handles it)
- [ ] E2E test exists (or manual test script documented)

Workflow: Reply / reply-all / forward

- [ ] Matches web steps exactly
- [ ] Handles same edge cases
- [ ] Same backend calls in same order
- [ ] Same data persisted (and cleared) as web
- [ ] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled (if web handles it)
- [ ] E2E test exists (or manual test script documented)

Workflow: Draft autosave/restore/delete

- [ ] Matches web steps exactly
- [ ] Handles same edge cases
- [ ] Same backend calls in same order
- [ ] Same data persisted (and cleared) as web
- [ ] Same success/failure user feedback
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
- [ ] Same backend calls in same order
- [ ] Same data persisted (and cleared) as web
- [ ] Same success/failure user feedback
- [ ] Offline / flaky network behavior handled (if web handles it)
- [ ] E2E test exists (or manual test script documented)

Workflow: Mailto URL -> draft -> compose

- [ ] Matches web steps exactly
- [ ] Handles same edge cases
- [ ] Same backend calls in same order
- [ ] Same data persisted (and cleared) as web
- [ ] Same success/failure user feedback
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

Integration: Voice (ElevenLabs)

- [ ] Equivalent native implementation exists
- [ ] Credentials/env vars configured
- [ ] Verified on all platforms
- [ ] Data/events match web

Integration: AI helpers (OpenAI/Perplexity-backed features)

- [ ] Equivalent native implementation exists
- [ ] Credentials/env vars configured
- [ ] Verified on all platforms
- [ ] Data/events match web

Integration: Deep linking + mailto handling

- [ ] Equivalent native implementation exists
- [ ] Credentials/env vars configured
- [ ] Verified on all platforms
- [ ] Data/events match web

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

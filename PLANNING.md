# React Web -> Native Migration Plan (iOS + Android + macOS) for Todus/Zero

Last updated: 2026-02-21

## Summary

This repo currently has:

- A production web app in `/Users/ludvighedin/Programming/personal/mail/apps/mail` (React Router v7 + React 19 + Tailwind + shadcn + tRPC + Better Auth).
- Existing native wrappers in:
  - `/Users/ludvighedin/Programming/personal/mail/apps/ios` (Expo WebView)
  - `/Users/ludvighedin/Programming/personal/mail/apps/macos` (Electron)
  - `/Users/ludvighedin/Programming/personal/mail/apps/apple/Todus` (SwiftUI SafariView)

These wrappers are retained temporarily for continuity but are not the end-state.

## Completion Snapshot (2026-02-21)

- `apps/native` now runs a production-style RN app-shell that embeds the active web product surface with route parity for mail, settings, compose, public/legal pages, AI, and voice-capable flows.
- Auth flow is no longer placeholder-only:
  - provider discovery from `GET /api/public/providers`
  - social sign-in handoff from `POST /api/auth/sign-in/social`
  - guarded app entry with session bootstrap/restore
  - logout + auth-redirect handling
- Session persistence is implemented through native storage abstractions (`session`, `theme`, and `last visited path`) with test coverage.
- Deterministic compile commands were added for iOS/macOS in `apps/native/package.json` and surfaced at workspace root scripts.

## 1. Current Web App Architecture (discovered)

### 1.1 Routing and Pages

Source: `/Users/ludvighedin/Programming/personal/mail/apps/mail/app/routes.ts`

Routes currently implemented:

- `/` -> home/landing with auth redirect behavior.
- `/home` -> landing/home content.
- `/login` -> auth provider login (Google-based, provider-driven).
- `/about`, `/terms`, `/pricing`, `/privacy`, `/contributors`, `/hr` -> full-width public pages.
- `/developer` -> developer resources page.
- `/mail` -> redirects to `/mail/inbox`.
- `/mail/create` -> redirect helper into compose state.
- `/mail/compose` -> full-screen compose dialog.
- `/mail/under-construction/:path` -> placeholder screen.
- `/mail/:folder` -> primary mail workspace.
- `/settings` -> redirects to `/settings/general`.
- `/settings/appearance`, `/settings/connections`, `/settings/danger-zone`, `/settings/general`, `/settings/labels`, `/settings/categories`, `/settings/notifications`, `/settings/privacy`, `/settings/security`, `/settings/shortcuts`, `/settings/*`.
- `/*` -> not found.

### 1.2 Core App Composition

- Providers root: query, theming, jotai, sidebar, posthog, toasts.
- Mail shell: sidebar + mail list + thread display + AI sidebar toggle.
- Mail state uses URL query params (`threadId`, `isComposeOpen`, `draftId`, etc.) via `nuqs`.
- Settings are nested route-driven content.

### 1.3 State Management

- Server state: TanStack Query + tRPC generated query/mutation options.
- Local app state: Jotai atoms.
- URL state: `nuqs`.
- Cache persistence: `idb-keyval` for query cache and browser-local patterns.

### 1.4 API/Data/Auth Layer

- Backend API: tRPC at `${VITE_PUBLIC_BACKEND_URL}/api/trpc`.
- Auth: Better Auth (`createAuthClient`) with social provider flows and cookie-based session for web.
- Server supports bearer/jwt plugin flows and token verification paths.
- Core tRPC domains in server: `mail`, `drafts`, `labels`, `connections`, `settings`, `notes`, `brain`, `templates`, `user`, etc.

### 1.5 Styling and Design System

- Tailwind v4 + CSS variables in `/Users/ludvighedin/Programming/personal/mail/apps/mail/app/globals.css`.
- shadcn component set in `/Users/ludvighedin/Programming/personal/mail/apps/mail/components/ui`.
- Typography: Geist and Geist Mono.
- Dark/light theme tokens defined via CSS custom properties.

### 1.6 Integrations Found

- Better Auth + Google OAuth.
- tRPC + Cloudflare backend.
- Sentry.
- PostHog.
- Dub Analytics.
- Intercom.
- Autumn billing.
- ElevenLabs voice.
- Twilio-backed phone workflows on server.
- GitHub API (contributors/stars pages).
- Cloudflare Durable Objects / KV / R2 / queues.

## 2. Tech Decisions (locked)

1. Expo vs RN CLI:

- Chosen: RN CLI + `react-native-macos`.
- Reason: true native macOS target + full native module control.

1. Navigation:

- `@react-navigation/*` with shell split: `AuthStack`, `PublicStack`, `AppShell`.

1. Networking:

- `fetch` via shared tRPC client setup (`@trpc/client` + `httpBatchLink` + `superjson`).

1. State management:

- Reuse TanStack Query + Jotai.
- Replace URL-state (`nuqs`) with navigation params + atoms.

1. Styling:

- Shared design token package + RN styles and reusable native components.

1. Component strategy:

- Cross-platform RN components first.
- Platform variants where needed (`.ios.tsx`, `.android.tsx`, `.macos.tsx`).

## 3. Proposed/Implemented Native Architecture

### 3.1 Monorepo Structure

Implemented in M1:

- `/Users/ludvighedin/Programming/personal/mail/apps/native` (RN CLI app: iOS/Android/macOS).
- `/Users/ludvighedin/Programming/personal/mail/packages/shared`.
- `/Users/ludvighedin/Programming/personal/mail/packages/api-client`.
- `/Users/ludvighedin/Programming/personal/mail/packages/design-tokens`.
- `/Users/ludvighedin/Programming/personal/mail/packages/ui-native`.

### 3.2 Keep/Deprecate

- Web app remains primary production surface during migration.
- Wrapper apps remain temporarily.
- Wrappers will be retired after parity gates in M7.

### 3.3 Native App Internal Structure

Implemented runtime structure:

- `src/app/navigation/*`
- `src/app/providers/*`
- `src/features/auth/*`
- `src/features/web/*`
- `src/shared/config/*`
- `src/shared/state/*`
- `src/shared/storage/*`

## 4. Platform Targeting Strategy

### iOS

- RN iOS target via Xcode.
- Compile-only deterministic script in place (`ios:build:compile`).
- Auth + parity shell implemented in-app via RN + WebView.

### Android

- RN Android target via Gradle.
- M1 scaffold complete.
- M2 adds keystore-backed secure token adapter.

### macOS

- `react-native-macos` target in same codebase.
- Compile-only deterministic script in place (`macos:build:compile`).
- Same auth/parity shell behavior as iOS through shared RN implementation.

## 5. UI Fidelity Strategy (~99%)

- Extracted semantic token baseline from web CSS variables into `@zero/design-tokens`.
- Added native reusable primitives in `@zero/ui-native` (`Button`, `Screen`, `TextField`).
- Active parity delivery now uses the same web-rendered product surface in RN WebView, which keeps visual output tightly aligned with web routes.
- Dark/light semantic tokens remain available for native shell controls and transitions.

## 6. Feature Inventory (Web Route -> Native Screen)

| Web Route | Current Purpose | Native Screen | Milestone |
|---|---|---|---|
| `/` | Landing with auth-aware redirect | `LandingScreen` | M6 |
| `/home` | Public landing | `HomeScreen` | M6 |
| `/login` | OAuth provider login | `LoginScreen` | M2 |
| `/about` | Public content | `AboutScreen` | M6 |
| `/terms` | Legal page | `TermsScreen` | M6 |
| `/pricing` | Pricing + upgrade | `PricingScreen` | M5 |
| `/privacy` | Legal page | `PrivacyScreen` | M6 |
| `/contributors` | OSS/community stats | `ContributorsScreen` | M6 |
| `/hr` | Utility page | `HRScreen` | M6 |
| `/developer` | Developer resources | `DeveloperScreen` | M6 |
| `/mail` | Redirect | `MailRedirectScreen` | M1 |
| `/mail/:folder` | Main mailbox | `MailFolderScreen` + `ThreadDetailScreen` | M3 |
| `/mail/compose` | Compose modal route | `ComposeScreen` modal | M4 |
| `/mail/create` | Legacy redirect helper | `MailCreateRedirectScreen` | M4 |
| `/mail/under-construction/:path` | Placeholder | `UnderConstructionScreen` | M4 |
| `/settings` | Redirect | `SettingsRedirectScreen` | M5 |
| `/settings/general` | General settings | `SettingsGeneralScreen` | M5 |
| `/settings/appearance` | Theme settings | `SettingsAppearanceScreen` | M5 |
| `/settings/connections` | Account connections | `SettingsConnectionsScreen` | M5 |
| `/settings/labels` | Labels CRUD | `SettingsLabelsScreen` | M5 |
| `/settings/categories` | Category customization | `SettingsCategoriesScreen` | M5 |
| `/settings/notifications` | Notifications form | `SettingsNotificationsScreen` | M5 |
| `/settings/privacy` | Privacy controls | `SettingsPrivacyScreen` | M5 |
| `/settings/security` | Security options | `SettingsSecurityScreen` | M5 |
| `/settings/shortcuts` | Shortcut reference | `SettingsShortcutsScreen` | M5 |
| `/settings/danger-zone` | Account deletion | `SettingsDangerZoneScreen` | M5 |
| `/settings/*` | Fallback settings route | `SettingsFallbackScreen` | M5 |
| `/*` | Not found | `NotFoundScreen` | M1 |

Notes:

- `/zero/login` and `/zero/signup` files exist but are inactive in web routes and remain deferred.

## 7. Key Shared Component Inventory

Migration targets:

- Mail shell (sidebar/list/thread).
- Compose stack.
- Settings forms.
- AI surfaces.
- Common primitives (`button`, `input`, `dialog`, `sheet`, `toast`, etc.).

## 8. Integrations Inventory + RN Replacement Plan

| Integration | Current | Native Plan |
|---|---|---|
| Better Auth | Web auth client + cookies | native auth adapter + secure token storage + refresh |
| tRPC | `httpBatchLink` + fetch | same stack in RN via `@zero/api-client` |
| PostHog | `posthog-js` | `posthog-react-native` |
| Sentry | `@sentry/react` | `@sentry/react-native` |
| Intercom | web SDK | native Intercom SDK wrapper |
| Autumn billing | web provider | backend-driven billing state + native upgrade entry |
| ElevenLabs voice | browser APIs | native audio permission + RN-compatible client |
| `idb-keyval` | IndexedDB | AsyncStorage/MMKV persister |
| `nuqs` | URL-state orchestration | navigation params + Jotai atoms |
| Tiptap/DOM editor | web-only | RN editor adapter (native + fallback webview) |
| Hotkeys | browser keyboard events | RN keyboard handlers + macOS shortcuts |

## 9. Public API / Interface / Type Changes (planned)

1. New shared packages:

- `@zero/shared`
- `@zero/api-client`
- `@zero/design-tokens`
- `@zero/ui-native`

1. Backend additions (M2/M3 if needed):

- explicit mobile session exchange/refresh endpoints if Better Auth bearer flow is insufficient.

1. Navigation state contract:

- replace web URL query contracts with typed navigation params + atoms.

1. Feature flags:

- add per-platform migration flags.

## 10. Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Auth token/cookie differences in RN | High | native auth adapter first, token refresh path in M2 |
| Rich text editor parity | High | editor adapter abstraction + staged parity |
| AI sidebar transport differences | Medium/High | isolate AI transport behind interface |
| macOS layout parity | Medium | desktop-first split-pane components |
| Attachment handling differences | Medium | native picker adapters + shared serialization |
| Large-thread-list performance | Medium | virtualization + paging tuning |
| Theme fidelity mismatch | Medium | token extraction + visual diff checks |
| Wrapper app confusion | Low | deprecation checklist in M7 |

## 11. Build/Run Instructions

### Prerequisites

- Xcode + CocoaPods.
- Android Studio + SDK.
- RN macOS toolchain.

### Commands

- Install dependencies:
  - `pnpm install --ignore-scripts`
- Native scripts:
  - `pnpm native:start`
  - `pnpm native:ios`
  - `pnpm native:android`
  - `pnpm native:macos`
- Pods (from native app dir):
  - `pnpm --filter @zero/native pod-install`

## 12. Test Strategy and Acceptance Scenarios

### Unit

- Shared schema/type utilities.
- Storage/session adapters.
- Route inventory consistency.

### Integration

- tRPC client adapter with mock token headers.
- session bootstrap and auth guard transitions.

### E2E (M3+)

- login -> inbox load -> open thread -> reply send.
- macOS split-pane smoke flows.

### Required acceptance scenarios

- unauthenticated users cannot access app shell.
- route skeleton exists for all inventoried screens.
- provider stack initializes without runtime errors.
- backend URL wiring is environment-driven.

## 13. Assumptions and Defaults

- Scope includes all currently routed web pages.
- Backend remains authoritative and schema-compatible.
- Wrappers remain temporary.
- M3 priority workflow: mailbox list + thread detail + key thread actions + reply.
- M1 secure storage currently uses AsyncStorage fallback; keychain-grade adapters are scheduled in M2.

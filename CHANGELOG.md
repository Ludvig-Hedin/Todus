# Project Changelog

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

- **Global Branding**: Renamed "Zero" to "Todus" across configuration, internationalization files (*.json), static pages, and the footer.
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

[2026-02-21] [Feature] Integrated real TRPC data for the native Thread list (N3-05) via useQuery hook on MailFolderScreen and ThreadListItem (apps/native/src/features/mail/*).

[2026-03-01] [Fix] Fixed chat modal opacity overlay, restricted pricing dialog trigger area to primary CTA button, and resolved chat connection Error code 400 by adjusting unsupported gpt-5 model name configuration to gpt-4o. (apps/mail/components/ui/ai-sidebar.tsx, apps/mail/components/create/ai-chat.tsx, apps/server/.dev.vars).

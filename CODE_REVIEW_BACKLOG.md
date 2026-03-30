# Code Review Backlog

Maintained by the automated code-review agent. Updated on each review session.

---

## CRITICAL

### CR-001: Auth bypass lacks development-only guard
- **Area/Scope:** `web/auth`
- **Type:** security
- **Impact:** user-facing
- **Risk:** high
- **Files:** `apps/mail/lib/auth-client.ts`, `apps/mail/lib/auth-proxy.ts`, `apps/mail/providers/query-provider.tsx`
- **Summary:** `VITE_PUBLIC_PARITY_AUTH_BYPASS` completely bypasses authentication when set. The `VITE_PUBLIC_` prefix means it is bundled into the client JS. If accidentally set in a production build, all authentication is bypassed with a fixed fake user (`parity-bypass-user`). There is no `import.meta.env.DEV` guard to ensure it is tree-shaken in production builds.
- **Suggested approach:** Add `import.meta.env.DEV &&` before each env var check so Vite's dead-code elimination removes the bypass in production builds.
- **Status:** `auto-fixed` — Added `import.meta.env.DEV` guards in auth-client.ts, auth-proxy.ts, and query-provider.tsx (2026-03-03).

### CR-002: Billing placeholder product ID `'pro-example'`
- **Area/Scope:** `ios/billing`
- **Type:** bug
- **Impact:** user-facing
- **Risk:** high
- **Files:** `apps/ios/app/(app)/settings/billing.tsx:27`
- **Summary:** The monthly product ID is `'pro-example'`, which appears to be a placeholder. Annual uses `'pro_annual'`. If shipped, monthly billing will fail or attempt a non-existent product.
- **Suggested approach:** Replace with the actual monthly product ID from Autumn/Stripe config.
- **Status:** `open` — Requires knowledge of the actual product ID; cannot auto-fix.

### CR-003: Billing mutations use `bearerToken!` non-null assertion
- **Area/Scope:** `ios/billing`
- **Type:** bug
- **Impact:** user-facing
- **Risk:** high
- **Files:** `apps/ios/app/(app)/settings/billing.tsx:74,95,121`
- **Summary:** `bearerToken` is derived from a Jotai atom. If the session expires while the billing screen is mounted, mutations will send `Bearer null` to the API. No early-return guard exists inside mutation functions.
- **Suggested approach:** Add `if (!bearerToken) throw new Error('Session expired')` inside each `mutationFn`.
- **Status:** `open` — Requires careful review of the billing flow UX.

### CR-004: No URL validation on billing/checkout URLs (SSRF/Open Redirect risk)
- **Area/Scope:** `ios/billing`
- **Type:** security
- **Impact:** user-facing
- **Risk:** high
- **Files:** `apps/ios/src/shared/integrations/autumn.ts:48-66,128-153`
- **Summary:** `extractUrl` blindly passes backend URLs to `Linking.openURL()`. No protocol or domain validation. A compromised backend could open arbitrary URLs.
- **Suggested approach:** Validate URLs start with `https://` and optionally allowlist known billing domains.
- **Status:** `open`

## WARNING

### CR-005: Console.log with sensitive data in Apple Sign-In (iOS)
- **Area/Scope:** `ios/auth`
- **Type:** security
- **Impact:** internal
- **Risk:** medium
- **Files:** `apps/ios/app/(auth)/login.tsx:149,157,172`
- **Summary:** `console.log` statements log auth URLs, idToken presence, and full response JSON in production. Should be gated behind `__DEV__`.
- **Suggested approach:** Wrap all Apple Sign-In console.log calls in `if (__DEV__)` guards.
- **Status:** `auto-fixed` — Added `__DEV__` guards (2026-03-03).

### CR-006: Apple Sign-In missing `response.ok` check before JSON parse
- **Area/Scope:** `ios/auth`
- **Type:** bug
- **Impact:** user-facing
- **Risk:** medium
- **Files:** `apps/ios/app/(auth)/login.tsx:171`
- **Summary:** `response.json()` is called without checking `response.ok`. A 5xx error with non-JSON body would throw an unhelpful error.
- **Suggested approach:** Add `if (!response.ok)` check before parsing JSON.
- **Status:** `auto-fixed` — Added response status check (2026-03-03).

### CR-007: Apple Sign-In silent success when identityToken is null
- **Area/Scope:** `ios/auth`
- **Type:** bug
- **Impact:** user-facing
- **Risk:** medium
- **Files:** `apps/ios/app/(auth)/login.tsx:151`
- **Summary:** If `credential.identityToken` is null (can happen on subsequent sign-ins where Apple doesn't re-provide data), the function completes without setting a session or showing an error.
- **Suggested approach:** Add an else clause that sets an error message when identityToken is missing.
- **Status:** `auto-fixed` — Added else clause with error message (2026-03-03).

### CR-008: Duplicate comment line in auth-providers.ts
- **Area/Scope:** `server/auth`
- **Type:** refactor
- **Impact:** internal
- **Risk:** low
- **Files:** `apps/server/src/lib/auth-providers.ts`
- **Summary:** `//       disableProfilePhoto: true,` appears twice in the commented-out Microsoft provider section.
- **Suggested approach:** Remove the duplicate line.
- **Status:** `auto-fixed` — Removed duplicate comment (2026-03-03).

### CR-009: `hasAutumnProAccess` overly permissive (billing)
- **Area/Scope:** `ios/billing`
- **Type:** bug
- **Impact:** user-facing
- **Risk:** medium
- **Files:** `apps/ios/src/shared/integrations/autumn.ts:103-118`
- **Summary:** Checks `stripe_id` presence and `products.length > 0` as Pro indicators, but Stripe creates customer records for free users too, and cancelled subscriptions may still have products.
- **Suggested approach:** Verify product/subscription status (active, cancelled, past_due) rather than just existence.
- **Status:** `open`

### CR-010: Assistant stale closure risk with `autoSpeak`
- **Area/Scope:** `ios/assistant`
- **Type:** bug
- **Impact:** user-facing
- **Risk:** medium
- **Files:** `apps/ios/app/(app)/assistant.tsx`
- **Summary:** `streamAssistantMessage` captures `autoSpeak` from closure. Since `useMutation` callbacks may hold stale function references, `autoSpeak` could always read `false` (initial state) when API responses arrive.
- **Suggested approach:** Use a ref for `autoSpeak` value, or restructure the callback to read current state.
- **Status:** `open`

### CR-011: Assistant Clear button doesn't stop ongoing speech
- **Area/Scope:** `ios/assistant`
- **Type:** bug
- **Impact:** user-facing
- **Risk:** low
- **Files:** `apps/ios/app/(app)/assistant.tsx`
- **Summary:** Pressing "Clear" removes messages but doesn't call `Speech.stop()`. Audio continues playing for a cleared conversation.
- **Suggested approach:** Call `stopVoicePlayback()` alongside `setMessages([])` in the Clear button handler.
- **Status:** `open`

## INFO

### CR-012: `babel-plugin-react-compiler` is an RC version
- **Area/Scope:** `ios/build`
- **Type:** DX
- **Impact:** internal
- **Risk:** low
- **Files:** `apps/ios/package.json`
- **Summary:** `babel-plugin-react-compiler: 19.1.0-rc.2` is a release candidate. May have stability issues.
- **Suggested approach:** Monitor for stable release and upgrade when available.
- **Status:** `open`

### CR-013: Non-standard `fontWeight: '650'` in assistant styles
- **Area/Scope:** `ios/assistant`
- **Type:** bug
- **Impact:** user-facing
- **Risk:** low
- **Files:** `apps/ios/app/(app)/assistant.tsx` (styles)
- **Summary:** `'650'` is not a standard CSS/RN font weight. iOS may round to nearest, but behavior is platform-dependent.
- **Suggested approach:** Use `'600'` (semibold) or `'700'` (bold).
- **Status:** `open`

### CR-014: Missing `keyboardDismissMode` on assistant ScrollView
- **Area/Scope:** `ios/assistant`
- **Type:** DX
- **Impact:** user-facing
- **Risk:** low
- **Files:** `apps/ios/app/(app)/assistant.tsx`
- **Summary:** Chat ScrollView lacks `keyboardDismissMode="interactive"`, so keyboard doesn't dismiss on scroll.
- **Suggested approach:** Add `keyboardDismissMode="interactive"` to the ScrollView.
- **Status:** `open`

### CR-015: Missing accessibility labels on assistant voice buttons
- **Area/Scope:** `ios/assistant`
- **Type:** DX
- **Impact:** user-facing
- **Risk:** low
- **Files:** `apps/ios/app/(app)/assistant.tsx`
- **Summary:** Voice action Pressable components lack `accessibilityLabel` and `accessibilityRole` props.
- **Suggested approach:** Add appropriate accessibility props.
- **Status:** `open`

### CR-016: CORS hardcoded `localhost` fallback
- **Area/Scope:** `server/cors`
- **Type:** security
- **Impact:** internal
- **Risk:** low
- **Files:** `apps/server/src/main.ts`
- **Summary:** `allowedDomains` includes `localhost` as a fallback. Low risk since CORS from localhost requires local attacker, but not ideal for production.
- **Suggested approach:** Gate `localhost` behind a development environment check.
- **Status:** `open`

### CR-017: AuthService logs sensitive auth response data
- **Area/Scope:** `ios/auth`
- **Type:** security
- **Impact:** internal
- **Risk:** medium
- **Files:** `apps/ios/Todus/Todus/Services/Auth/AuthService.swift`
- **Summary:** Recent Apple and Google auth debugging logged raw response metadata and callback URLs. On affected paths, that can expose session cookies or callback tokens in device logs.
- **Suggested approach:** Remove or redact the sensitive fields and keep any detailed logging behind `#if DEBUG` with non-secret summaries only.
- **Status:** `auto-fixed` — Replaced sensitive logs with debug-only status/scheme logging in `AuthService.swift` (2026-03-27).

### CR-018: Todus Xcode target missing locally referenced source files
- **Area/Scope:** `ios/build`
- **Type:** bug
- **Impact:** user-facing
- **Risk:** medium
- **Files:** `apps/ios/Todus/Todus.xcodeproj/project.pbxproj`, `apps/ios/Todus/Todus/Services/NetworkMonitor.swift`, `apps/ios/Todus/Todus/Features/Calendar/CalendarPermissionView.swift`
- **Summary:** The app referenced `NetworkMonitor` and `CalendarPermissionView`, but neither source file had been added to the Xcode target, causing simulator builds to fail despite the files existing on disk.
- **Suggested approach:** Add the missing file references and source build entries to the Xcode project whenever new Swift files are introduced outside Xcode.
- **Status:** `auto-fixed` — Added both files to the Todus target in `project.pbxproj` and verified the simulator build succeeds (2026-03-27).

### CR-019: Tracked CustomTabBar implementation drifted from intended UI
- **Area/Scope:** `ios/navigation`
- **Type:** bug
- **Impact:** user-facing
- **Risk:** medium
- **Files:** `apps/ios/Todus/Todus/Features/Tasks/CustomTabBar.swift`
- **Summary:** The tracked `CustomTabBar.swift` in the target had diverged from the intended implementation and no longer type-checked, while a newer untracked copy existed elsewhere. That left the app building the wrong file.
- **Suggested approach:** Keep the tracked target file aligned with the implementation used by `MainTabView`, or move the source of truth into one location and update the Xcode project accordingly.
- **Status:** `auto-fixed` — Replaced the tracked target file with the intended glass-pill implementation and verified the build (2026-03-27).

### CR-020: Voice secret sent from client bundle undermines server auth
- **Area/Scope:** `web/ai`, `server/ai`
- **Type:** security
- **Impact:** user-facing
- **Risk:** medium
- **Files:** `apps/mail/lib/server-tool.ts`, `apps/server/src/routes/ai.ts`
- **Summary:** `VITE_PUBLIC_VOICE_SECRET` is sent as `X-Voice-Secret` header from the browser. Since `VITE_PUBLIC_*` vars are bundled into client JS, anyone can extract the secret and call `/api/ai/do/:action` directly. The server treats this header as an auth gate.
- **Suggested approach:** Replace with Bearer token auth (user's session token) for client-initiated AI tool calls. Currently `VOICE_SECRET` is empty string for local dev, so risk depends on production config.
- **Status:** `open`

### CR-021: Wildcard CORS on `/api/ai/do/*` routes
- **Area/Scope:** `server/ai`
- **Type:** security
- **Impact:** user-facing
- **Risk:** medium
- **Files:** `apps/server/src/routes/ai.ts:174`
- **Summary:** `Access-Control-Allow-Origin: *` on `/do/*` routes combined with weak `X-Voice-Secret` auth allows any website to call tool execution endpoints.
- **Suggested approach:** Restrict CORS to known origins (reuse the trusted origins list from auth config).
- **Status:** `open`

### CR-020b: Voice permission API uses deprecated recorder permission call
- **Area/Scope:** `ios/voice`
- **Type:** DX
- **Impact:** internal
- **Risk:** low
- **Files:** `apps/ios/Todus/Todus/Features/AI/AIChatView.swift`, `apps/ios/Todus/Todus/Features/Voice/VoiceInputButton.swift`
- **Summary:** The build still emits deprecation warnings for `requestRecordPermission`. This is low-risk, but it should be migrated to `AVAudioApplication.requestRecordPermission` to stay aligned with the current iOS API surface.
- **Suggested approach:** Update both call sites to the iOS 17+ API with a compatibility branch for older OS versions if needed.
- **Status:** `open`

### CR-022: Full WIP snapshot committed as single safety backup
- **Area/Scope:** `repo/git`
- **Type:** design-debt
- **Impact:** internal
- **Risk:** low
- **Files:** (branch `backup/safety-2026-03-30-full-wip` on origin)
- **Summary:** Before the 2026-03-30 macOS review, all local changes were captured in one commit and pushed for recovery. `main` was fast-forwarded to include that snapshot. Granular per-feature history for that batch was not preserved.
- **Suggested approach:** If needed, split history in a dedicated session (e.g. interactive rebase) without rewriting shared `main` unless the team agrees.
- **Status:** `open`

### CR-023: macOS AI chat HTTP 401 without silent refresh
- **Area/Scope:** `macos/ai`
- **Type:** bug
- **Impact:** user-facing
- **Risk:** low
- **Files:** `apps/macos/TodusMac/Services/AI/MacAIChatService.swift`
- **Summary:** `MacAIChatService` treated every 401 as a hard session expiry. iOS already attempts `attemptSilentRefresh()` first.
- **Suggested approach:** Mirror iOS: refresh, then prompt retry or set `isSessionExpired`.
- **Status:** `auto-fixed` — Implemented 2026-03-30.

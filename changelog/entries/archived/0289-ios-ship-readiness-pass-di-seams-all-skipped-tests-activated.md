---
id: 0289
title: "iOS ship-readiness pass: DI seams, all skipped tests activated, UI test target, voice mic lock, autosave migration, debounced policy push"
status: archived
category: Changed
release_date: 2026-05-20
source: CHANGELOG.md
---

## [2026-05-20] iOS ship-readiness pass: DI seams, all skipped tests activated, UI test target, voice mic lock, autosave migration, debounced policy push

Third pass closes the "complete after small fixes" gaps from the 2026-05-17 review. **67 unit tests pass, 0 fail, 0 skipped** (was 66 / 0 / 15). UI test target compiles. All recommended hardening from the strict review landed.

**Tests — zero skipped**

- All 15 previously-skipped tests now active and passing, plus 1 new test (pagination dedup no-op when incoming is older). DI seams added without changing any public API:
  - `AuthService`: `AuthTransport` protocol + `URLSession` conformance; `classifyCallbackTokens` extracted from `completeAuthentication`; `beginPendingAuthFlow`/`endPendingAuthFlow`/`isPendingAuthFlowActive` helpers extracted from `signInWithGoogle`.
  - `TodosAPIClient`: internal init with custom `URLSessionConfiguration` injection.
  - `AIChatService`: `classifyFlushDecision` nonisolated static helper extracted from `flushTokenBuffer`.
  - `EmailService`: `mergePages` static helper extracted from `performLoadThreads`.
  - `NetworkMonitor`: `PathProviding` protocol + `NWPathProvider` default impl + internal init.
  - `RemoteFirstTaskParsingService`: `RemoteTaskParsingTransport` protocol + internal init.
  - `AppleRemindersSyncService`: `EKReminderStoring` protocol + internal init; test-only readbacks (`_test_inFlightUpserts`, `_test_coalescedRetryCount`, `_test_recordPendingUpsert`).
- All new init params have defaults pointing at real implementations; existing call sites untouched.

**UI test target stood up**

- `TodusUITests` target wired (xcodegen). `--ui-testing` launch-arg detected in `AppServices.init` injects fake bearer + onboarding flags + `hasReachedMainTab` so XCUITests skip auth and land on MainTab deterministically. Startup network calls (`refreshSession`, AI snapshot fetches, shared profile load) gated behind `!isUITestingMode`.
- 3 test files in `TodusUITests/`: `TodusUITests.swift` (smoke), `CriticalFlowsTests.swift` (C1-C5 regression smoke via simulated deep link / notification / mutation pending state), `ParitySmokeTests.swift` (startup card on fresh install, voice settings accessibility, docs empty state, automation policy reachability).
- UI test target compiles clean (`xcodebuild build-for-testing`). UI test execution requires booted simulator (sandbox blocks here — verify with `xcodebuild test -only-testing:TodusUITests` locally).

**Voice race + autosave migration + policy debounce**

- **Voice mic lock** ([`Services/Voice/VoiceMicLock.swift`](apps/ios/Todus/Todus/Services/Voice/VoiceMicLock.swift)) — cooperative `@MainActor @Observable` lock with `acquire(owner:)` / `release(owner:)`. Wired into both `VoiceSessionCoordinator` (owner: "coordinator") and `VoiceChatViewModel` (owner: "modal"). Siri Shortcut + modal-open at the same time can't double-attach AVAudioEngine. Same class of bug as H17.
- **Compose autosave migration** ([`Features/Email/EmailComposeView.swift`](apps/ios/Todus/Todus/Features/Email/EmailComposeView.swift)) — `migrateLegacyAutosaveIfNeeded()` runs once on first restore: copies `reply.<threadId>` / `replyAll.<threadId>` UserDefaults blobs to the unified `compose.<threadId>` key (replyAll wins if both present), then deletes the legacy keys. Idempotent.
- **EmailAutomationPolicyView debounced push** — 300ms debounced `saveSharedAIProfile` per change instead of `onDisappear`-only. Crash mid-edit no longer strands changes. `.onDisappear` still flushes as fallback. `AssistantAutomationPolicy` + `AssistantQuietHours` + `AssistantAutoSendScenario` gained `Equatable` for `onChange(of:)`.

**Docs dedup + startup migration tightened**

- `DocsService.refresh()` no longer auto-creates a "Personal" workspace when the server already has one (case-insensitive name check). On 409/422 race, refetches and uses the server's existing workspace.
- `hasSeenStartupCard` migration: dropped unreliable `hasPersistedBearerToken` signal (Keychain survives uninstall on iOS — could silently skip card on fresh reinstall). Added new positive signal `Keys.hasReachedMainTab`, set in `MainTabView.onAppear` the first time the tab shell appears. Migration: card skipped only when `hasReachedMainTab` OR (`isAuthenticated && any prior onboarding flag`).

**Verification**

- `xcodebuild build` → **BUILD SUCCEEDED**
- `xcodebuild build-for-testing` → **TEST BUILD SUCCEEDED**
- `xcodebuild -only-testing:TodusTests test` → **TEST SUCCEEDED** (67 / 0 / 0)
- UI tests pending booted simulator (run locally).

**Manual follow-ups (user)**

1. Open Xcode + run UI tests on simulator/device.
2. AI conversation history + AppTheme avatar cache migrations run silently on first launch (transparent).
3. Activate Siri Shortcut "Start Voice Assistant" via Shortcuts app.
4. Apple `com.apple.developer.mail-client` entitlement still pending (pre-existing TODO).
5. Review + commit when ready.

---
id: 0220
title: "iOS Ship-Readiness Pass (2026-05-20) — DONE"
status: done
tags: [task-md, sprint]
files: [Services/Voice/VoiceMicLock.swift]
created: 2026-05-20
source: TASK.md
---

> Source context: TASK.md

## iOS Ship-Readiness Pass (2026-05-20) — DONE

Third pass closing the "complete after small fixes" gaps from 2026-05-17 strict review.

- `DONE` **All 15 skipped tests activated.** 67 unit tests pass, 0 fail, 0 skipped (was 66 / 0 / 15). DI seams added without changing public API: `AuthService.AuthTransport` + `classifyCallbackTokens` + `pendingAuthFlow` helpers, `TodosAPIClient` URLSessionConfiguration injection, `AIChatService.classifyFlushDecision`, `EmailService.mergePages`, `NetworkMonitor.PathProviding`, `RemoteFirstTaskParsingService.RemoteTaskParsingTransport`, `AppleRemindersSyncService.EKReminderStoring` + test-only readbacks.
- `DONE` **TodusUITests target stood up.** xcodegen wires the target; `--ui-testing` launch arg in `AppServices.init` injects fake bearer + onboarding flags so XCUITests skip auth. 3 test files cover C1-C5 critical fixes + parity smoke (startup card, voice settings, docs empty state, automation policy reachability). UI target compiles clean; execution requires booted simulator (run locally).
- `DONE` **Voice mic lock** (`Services/Voice/VoiceMicLock.swift`) — cooperative lock between `VoiceSessionCoordinator` (owner "coordinator") and `VoiceChatViewModel` (owner "modal"). Prevents AVAudioEngine double-attach race when Siri Shortcut + modal triggered concurrently.
- `DONE` **Compose autosave migration** (`EmailComposeView.migrateLegacyAutosaveIfNeeded`) — copies `reply.<threadId>` / `replyAll.<threadId>` UserDefaults blobs to unified `compose.<threadId>` key on first restore. ReplyAll wins if both. Idempotent.
- `DONE` **EmailAutomationPolicyView debounced push** — 300ms debounce on `saveSharedAIProfile` per change instead of `onDisappear`-only. `.onDisappear` still flushes. `AssistantAutomationPolicy` gained `Equatable`.
- `DONE` **DocsService Personal workspace dedup** — case-insensitive name check before auto-create; refetches on 409/422 race.
- `DONE` **Startup card migration tightened** — dropped unreliable `hasPersistedBearerToken` signal (Keychain survives uninstall). New positive `Keys.hasReachedMainTab` signal set in `MainTabView.onAppear`. Migration: card skipped only when `hasReachedMainTab` OR (`isAuthenticated && any prior onboarding flag`).

**Verification**: `xcodebuild build` SUCCEEDED, `xcodebuild build-for-testing` SUCCEEDED, `xcodebuild -only-testing:TodusTests test` SUCCEEDED (67/0/0).

**Manual follow-ups for user**:
1. Open Xcode, run UI tests on simulator/device.
2. AI conversation + avatar cache migrations are silent first-launch.
3. Activate "Start Voice Assistant" Siri Shortcut via Shortcuts app.
4. Apple `com.apple.developer.mail-client` entitlement still pending (pre-existing TODO).

---
id: 0285
title: "iOS parity sweep: voice + docs + automation + tests + startup card"
status: archived
category: Docs
release_date: 2026-05-17
source: CHANGELOG.md
---

## [2026-05-17] iOS parity sweep: voice + docs + automation + tests + startup card

Second pass on iOS (after morning bug-hunt + ux-polish): closed remaining macOS→iOS parity gaps and stood up a real test suite. 5 parallel agents, full integration `xcodebuild` clean + `xcodebuild test` green.

**New iOS features (parity with macOS)**

- [Voice] **Voice assistant lifecycle on iOS** — was modal-only; now full coordinator-driven session. New `Services/Voice/`: `VoiceSessionCoordinator.swift` (391L, state machine: idle/connecting/listening/speaking/toolRunning/error, owns lifecycle + transcript persistence via `ai.saveConversation`), `VoiceSystemPromptClient.swift` (server-fetched persona with 60s TTL cache + offline fallback — replaces locally-built stale prompt), `VoiceToolRegistry.swift` (Gemini function declarations + `VoiceToolExecutor` protocol + iOS adapter calling `AIChatService.processVoiceToolCall`), `VoiceAudioCapture.swift` (AVAudioEngine 16kHz PCM16 capture). `VoiceIntent.swift` — `StartVoiceAssistantIntent` AppIntent + `TodusVoiceAppShortcuts` provider so Siri Shortcut serves as the iOS-equivalent of macOS's global hotkey. `Features/Settings/VoiceAssistantSettingsView.swift` mirrors macOS `voiceAssistantSection` (enable toggle, auto-stop idle toggle, Siri Shortcut hint with Shortcuts.app deep-link, reset persona cache, live status row). Wired into `AppServices` + `TodosApp` (`.task` subscribes to `.todusStartVoiceSession` notification, hydrates SwiftData main context, calls `coordinator.start()`).
- [Docs] **Native iOS Docs shell** — was web shim only. New `Domain/DocTypes.swift` (DTOs mirroring macOS), `Services/Docs/DocsService.swift` (`@MainActor @Observable`, refresh/list/create/update/delete/move/star/togglePin/search, auto-creates Personal workspace), `Features/Docs/DocsListView.swift` (NavigationSplitView on iPad, NavigationStack on iPhone, recursive nested doc rows, pull-to-refresh, context menu, swipe actions, empty state, ~290L), `Features/Docs/DocEditorView.swift` (thin native nav wrapper around existing `DocsWebView` — preserves web fallback). `DocsWebView` gained optional `docId` param for deep linking; legacy callers unchanged. `MoreSheetView` exposes native Docs + "Docs (Web)" fallback (no removal of legacy).
- [Settings] **Email automation policy controls on iOS** — `Features/Settings/EmailAutomationPolicyView.swift` (excluded-sender add/list/swipe-to-delete, auto-send experiment toggle with confirmation, workday start/end hour pickers, reset to recommended). NavigationLink added in `SettingsView.swift::emailSection`. Persists via AppServices, pushes on disappear.
- [Tasks] **Compound intent parser refinements on iOS** — `Services/Parsing/CompoundIntentParser.swift` patched with word-boundary regex (port of macOS refinements) — handles Swedish "och" + English "and" connectors with proper `\b` boundary checks. `RemoteFirstTaskParsingService` exposes `parseCompoundLocally(...)` hook so callers can get multi-intent results.
- [Onboarding] **Branded startup card on iOS** — `App/StartupOnboardingView.swift` (~150L). Hero squircle logo, "Get started" + "I already have an account". Wired into `RootView` ahead of AuthView. Existing installs auto-skip via migration check (any prior onboarding flag set or authenticated session). Matches macOS `MacStartupOnboardingView` brand presence.

**Tests — stood up real coverage**

- Before: 2 files, 9 tests, ~5% coverage. After: 10 files, **66 tests pass, 0 fail, 15 skipped** (skipped tests document required DI seams).
- New: `AuthServiceTests` (12 tests — C1 deep-link rejection, preloadTokens determinism, init→auth transition, token preview safety), `TodosAPIClientTests` (8 tests — superjson Date-meta envelope, omitted-meta plain payload, nested-date dotted path, batch wrap with String/Int H16 regression pin), `AIChatServiceTests` (12 tests — CRLF / LF classify, `[DONE]` with/without trailing CR H14 pin, heartbeat skip, chunk-boundary residual, replay end-to-end, malformed-JSON tolerance), `EmailServiceTests`, `AppleRemindersSyncServiceTests`, `NetworkMonitorTests`, `AppThemeAvatarCacheTests`, `RemoteFirstTaskParsingServiceTests`.
- Minimal non-breaking seams added: `TodosAPIClient.swift` exposes `superjsonWrap_forTesting` via `TodosAPIClientTestSeam`; `AIChatService.swift` extracts `SSELineParser` enum (production loop unchanged — pure helper).
- `TodosUITests` target stood up via xcodegen. Smoke test (`app.launch()` + window-exists). Manual follow-up: implement `--ui-testing` launch-arg stub in `AppServices` for deeper E2E.

**Infrastructure**

- [Build] **Duplicate `LocalModelStateStore.swift` resolved** — `App/LocalModelStateStore.swift` (51L stub placeholder) collided with `Services/AI/Local/LocalModelStateStore.swift` (188L real impl used by `ModelDownloadService` + `MLXInferenceService`). Renamed stub to `LocalModelStateStore_DEPRECATED.swift`, emptied class definition. Was blocking all builds. Safe to delete from disk in next cleanup.

**Verification**

- `xcodebuild -project apps/ios/Todus/Todus.xcodeproj -scheme Todus -sdk iphonesimulator build` → **BUILD SUCCEEDED**
- `xcodebuild ... -only-testing:TodusTests test` → **TEST SUCCEEDED** (66 / 0 / 15, 0.30s)

**Manual follow-ups**

1. Open in Xcode + run on simulator/device (sandbox blocks CoreSimulator).
2. Activate Siri Shortcut "Start Voice Assistant" via Shortcuts app to enable voice.
3. Conversation history migrates Keychain → file system on first launch (transparent).
4. AppTheme avatar cache migrates UserDefaults → file system on first launch (transparent).
5. Implement `--ui-testing` AppServices stub when ready for deeper E2E UI tests.
6. Apple `com.apple.developer.mail-client` entitlement still pending (existing TODO).

Full detail: `TASK.md` "Current iOS Parity + Hardening Sprint" + per-bug entries in `CODE_REVIEW_BACKLOG.md` "2026-05-17 — iOS Bug-Hunt + UX-Polish Audit".

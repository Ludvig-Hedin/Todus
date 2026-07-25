---
id: 0288
title: "Bug-hunt + UX-polish: iOS app sweep (6 surfaces)"
status: archived
category: Fixed
release_date: 2026-05-17
source: CHANGELOG.md
---

## [2026-05-17] Bug-hunt + UX-polish: iOS app sweep (6 surfaces)

Multi-agent audit + remediation across iOS surfaces. 5 critical + 17 high + 46 medium bugs + 84 polish items addressed. Full integration `xcodebuild` clean.

**Critical/security**

- [Auth] **Deep-link token-injection blocked** ([`packages/swift-auth/Sources/TodusAuth/AuthService.swift`](packages/swift-auth/Sources/TodusAuth/AuthService.swift)) — `handleAuthCallback` strictly requires unexpired `pendingAuthFlowExpiresAt` regardless of `isAuthenticated`. Apple Sign In also sets the window (was Google-only) + adds nonce. Sentinel consumed on accept → single-use deep links.
- [Auth] **Stale refresh-token leak across re-login** (`AuthService.completeAuthentication`) — JWT-only branch clears `refreshToken`/`currentSessionId`; first two branches clear `currentSessionId` when callback omits one. Prevents cross-account session bleed.
- [Auth] **Sign-out hardened** — best-effort server revoke + synchronous Keychain delete on `signOut()` so suspend mid-logout can't resurrect tokens.
- [Notifications] **Notification taps revived** ([`apps/ios/Todus/Todus/App/TodosApp.swift`](apps/ios/Todus/Todus/App/TodosApp.swift)) — default-action branch routes email-thread, AI-conversation, due-task, email-reminder taps. Was dead — only `TASK_COMPLETE`/`TASK_SNOOZE` worked.
- [AI] **Mutation confirmation deadlock fixed** ([`Features/AI/AIChatView.swift`](apps/ios/Todus/Todus/Features/AI/AIChatView.swift), [`Services/AI/AIChatService.swift`](apps/ios/Todus/Todus/Services/AI/AIChatService.swift)) — `.confirmationDialog` bound to `pendingMutationConfirmation`. `send_email`/`update_calendar_event`/`delete_calendar_event` hung forever. `cancelStream` drains mutation continuations + resets `streamFailed`.
- [Calendar] **Permission view stuck loading after grant** ([`Features/Calendar/CalendarPermissionView.swift`](apps/ios/Todus/Todus/Features/Calendar/CalendarPermissionView.swift)) — `.onReceive(.todusCalendarAuthorizationDidChange)` + scenePhase re-read.

**High-impact**

- [Email] `EmailService` actions (`toggleStar`, `markAsSpam`, `markAsRead`, `markAsUnread`, `archiveThreads`) return `Bool`; star toggle rolls back on failure; pagination dedupe replaces in-place when newer.
- [Tasks] Capture rollback no longer races concurrent enrichment; `RemoteFirstTaskParsingService` preserves `lowConfidence`; Reminders sync bounded recursion (3 retries) + removed no-op guard.
- [Calendar] Day view fetches unified events (was Apple-only); Google event tap no-op fixed (provider-prefix strip + retry-then-alert); `EKWrapper` deleted-calendar force-unwrap removed.
- [AI] SSE parser trims `\r\n`; `flushTokenBuffer` bails on stale messageID; calendar snapshot invalidates on permission toggle; conversation persistence migrated Keychain → file system with `.completeFileProtection`.
- [Infra] TRPC body wrapped with minimal superjson (ISO-8601 Date meta); `JSONSerialization` uses `.fragmentsAllowed`; AVAudioEngine double-attach guarded; `NetworkMonitor` seeds from `currentPath`; `SubscriptionService.cancel` re-entrancy guard; `NotificationDigestService` routes via `TodosAPIClient`; `CreateSheet` validates `endDate > startDate`; AppTheme avatar cache → SHA-256 file storage; `AppPrimaryButtonStyle` uses `Color.accentColor`.

**UX polish (selected)**

- Email: archive swipe not red, send/refresh haptics, "Sending…" inline label, search-feedback distinguishes loading vs done, From row hidden on single account, recent-message relative timestamps.
- Tasks: complete/snooze haptics, context-menu delete confirmation, board column quick-add, 44pt tap targets, leading checkbox column in table view, "All clear" chip hides on truly empty, "Recent"/"Oldest" sort labels.
- Calendar: 44pt event tap targets, list empty-state CTA, scope-banner haptic+a11y, loading skeleton, long-press haptic, grid-tap creates event.
- AI: shimmer placeholder while streaming empty, always-rendered Send button, status pills in empty state (model + connected services), shuffle suggestions, contextual thinking copy from `searchState`, Share/Speak menu items, user bubble iPad maxWidth, `.updatesFrequently` VoiceOver trait.
- Infra: offline banner red tint + Retry CTA, cold-launch home skeleton, transient "Signing out…"/"Disconnect Gmail" HUDs replace blocking alerts, `@ScaledMetric` FAB, `InlineRefreshBadge` accepts `entity` for VoiceOver.
- Auth: stage-1 disabled during OTP loading, error banner auto-dismiss after 6s, OTP verify/resend spinner overlay (visible above keyboard), red email-validation hint, `canOpenURL` guard on mailto, accessibilityHints on social buttons, bell-icon accessibilityHidden.

**Verification**

- `swift build` (packages/swift-auth): Build complete.
- `xcodebuild -scheme Todus -sdk iphonesimulator build`: **BUILD SUCCEEDED** (full integration across all 6 surfaces).

**Manual follow-ups**

1. Open in Xcode and run on simulator/device — sandbox can't launch CoreSimulator for live UI smoke test.
2. AI conversation history migrates Keychain → `Application Support/ai-conversations.json` on first launch.
3. AppTheme avatar cache migrates UserDefaults blobs → file cache on first `loadFromCache`.
4. C1 single-use deep links non-replayable; confirm no legitimate flow needs replay (none expected).

Full per-bug detail in [`CODE_REVIEW_BACKLOG.md`](CODE_REVIEW_BACKLOG.md) under "2026-05-17 — iOS Bug-Hunt + UX-Polish Audit".

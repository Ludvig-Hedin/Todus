import SwiftUI
import SwiftData

/// Root view — routes between auth, onboarding, and the main tab shell.
/// Uses the new AuthService (Better-Auth) for authentication state.
struct RootView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext

    /// Tracks whether this is the initial render — suppresses transitions on cold start
    /// to prevent the half-screen layout bug caused by competing .move() animations
    /// when multiple state values are already determined from Keychain/UserDefaults.
    @State private var hasAppeared = false
    @State private var hasRunDeferredStartup = false
    /// Snapshot of how many onboarding steps THIS user's journey contains, taken
    /// once at sign-in. Returning users skip the welcome-tour / tab-bar steps (set
    /// done in `AppServices.init`), so the old hardcoded "of 5" lied — it showed
    /// "2 of 5" then dropped the user into the app after step 2. Reset on sign-out.
    @State private var onboardingTotalSnapshot: Int? = nil

    var body: some View {
        Group {
            if !services.hasSeenStartupCard && !services.authService.isAuthenticated {
                // One-shot branded entry — shown only for genuinely new installs.
                // Both CTAs flip `hasSeenStartupCard`, after which the regular
                // unauthenticated routing (AuthView → onboarding chain) takes over.
                StartupOnboardingView()
                    .transition(hasAppeared ? .opacity.combined(with: .move(edge: .trailing)) : .opacity)
            } else if services.authService.showsOnboarding {
                AuthView()
                    .transition(hasAppeared ? .opacity.combined(with: .move(edge: .trailing)) : .opacity)
            } else if !services.hasConfiguredGmailPrompt {
                GmailOnboardingView()
                    .transition(hasAppeared ? .opacity.combined(with: .move(edge: .trailing)) : .opacity)
            } else if !services.hasConfiguredRemindersPrompt {
                RemindersOnboardingView()
                    .transition(hasAppeared ? .opacity.combined(with: .move(edge: .trailing)) : .opacity)
            } else if !services.hasConfiguredNotificationsPrompt {
                NotificationsOnboardingView()
                    .transition(hasAppeared ? .opacity.combined(with: .move(edge: .trailing)) : .opacity)
            } else if !services.hasSeenWelcomeTour {
                // Optional product explainer with prominent Skip — runs once per
                // install. Surfaces what the app does before we ask the user to
                // customise the tab bar.
                WelcomeTourView()
                    .transition(hasAppeared ? .opacity.combined(with: .move(edge: .trailing)) : .opacity)
            } else if !services.hasConfiguredTabBarPrompt {
                // Tab-bar customization — iOS only because the native TabView is
                // capped at 4 configurable slots (+ the create FAB). The user
                // can always come back via Settings, so this step is also
                // skippable.
                TabBarOnboardingView()
                    .transition(hasAppeared ? .opacity.combined(with: .move(edge: .trailing)) : .opacity)
            } else {
                MainTabView()
                    .transition(hasAppeared ? .opacity : .identity)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let onboardingStep = onboardingStep {
                let onboardingTotal = onboardingTotal
                let progressText = String(
                    localized: "\(onboardingStep) of \(onboardingTotal)",
                    comment: "Compact onboarding progress label showing current step and total steps"
                )
                let progressAccessibilityLabel = String(
                    localized: "Onboarding step \(onboardingStep) of \(onboardingTotal)",
                    comment: "Accessibility label for onboarding progress"
                )
                HStack {
                    Spacer()
                    Text(progressText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(AppTheme.cardBorder.opacity(0.8), lineWidth: 1)
                                // Decorative stroke — outer Text already supplies the
                                // accessibility label; hiding the inner stops VoiceOver
                                // from reading the same string twice.
                                .accessibilityHidden(true)
                        )
                        .accessibilityLabel(progressAccessibilityLabel)
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.bottom, 6)
                .allowsHitTesting(false)
            }
        }
        // Single animation modifier prevents competing animation controllers from
        // producing stuck/offset frames on cold start.
        .animation(hasAppeared ? .snappy(duration: 0.3) : nil, value: services.hasSeenStartupCard)
        .animation(hasAppeared ? .snappy(duration: 0.3) : nil, value: services.authService.showsOnboarding)
        .animation(hasAppeared ? .snappy(duration: 0.3) : nil, value: services.hasConfiguredRemindersPrompt)
        .animation(hasAppeared ? .snappy(duration: 0.3) : nil, value: services.hasConfiguredGmailPrompt)
        .animation(hasAppeared ? .snappy(duration: 0.3) : nil, value: services.hasConfiguredNotificationsPrompt)
        .animation(hasAppeared ? .snappy(duration: 0.3) : nil, value: services.hasSeenWelcomeTour)
        .animation(hasAppeared ? .snappy(duration: 0.3) : nil, value: services.hasConfiguredTabBarPrompt)
        .animation(hasAppeared ? .snappy(duration: 0.3) : nil, value: services.authService.isAuthenticated)
        .onAppear {
            // Enable transitions only after the first frame renders.
            // DispatchQueue.main.async ensures SwiftUI has committed the initial layout.
            DispatchQueue.main.async { hasAppeared = true }
        }
        .task {
            guard !hasRunDeferredStartup else { return }
            hasRunDeferredStartup = true
            // UI tests inject auth via launch arg — skip the network bootstrap
            // so the deterministic seed is what the harness sees.
            guard !services.isUITestingMode else { return }
            await runDeferredStartupWork()
        }
        .task(id: services.authService.isAuthenticated) {
            guard services.authService.isAuthenticated else {
                // Signed out — clear the snapshot so the next sign-in measures its
                // own onboarding journey afresh.
                onboardingTotalSnapshot = nil
                return
            }
            // Capture the journey length once, now that the account's onboarding
            // flags are settled, so the "X of N" counter reflects the steps this
            // user will actually see instead of a hardcoded 5.
            if onboardingTotalSnapshot == nil {
                let remaining = remainingOnboardingSteps
                if remaining > 0 { onboardingTotalSnapshot = remaining }
            }
            guard !services.isUITestingMode else { return }
            await services.loadSharedAIProfile()
        }
    }

    @MainActor
    private func runDeferredStartupWork() async {
        let trace = PerformanceTrace.beginInterval(
            PerformanceTrace.rootStartup,
            message: "RootView deferred startup begin"
        )
        defer {
            PerformanceTrace.endInterval(
                PerformanceTrace.rootStartup,
                trace,
                message: "RootView deferred startup end"
            )
        }

        // Let the first interactive frame settle before kicking off background work.
        try? await Task.sleep(for: .milliseconds(350))
        // Hydrate the persistent avatar URL cache off the main thread. The cache used
        // to JSON-decode up to 5000 entries synchronously on first access from a view
        // body — a measured cold-start hang. Doing it here as part of deferred startup
        // keeps it off the splash → first-tab transition.
        await AvatarCache.shared.bootstrap()
        await services.authService.fetchUserProfile()
        // Note: loadSharedAIProfile() is intentionally NOT called here on a
        // signed-in launch — the `.task(id: services.authService.isAuthenticated)`
        // handler above already triggers it once authentication state is known,
        // and calling it from both places caused a duplicate request on every
        // signed-in cold start.

        // Delay legacy upgrade work until after the initial shell is usable.
        try? await Task.sleep(for: .milliseconds(150))
        await services.completeAuthUpgradeIfNeeded(in: modelContext)
    }

    /// The five onboarding steps in display order, each flagged as still-pending.
    private var onboardingPendingFlags: [Bool] {
        [
            !services.hasConfiguredGmailPrompt,
            !services.hasConfiguredRemindersPrompt,
            !services.hasConfiguredNotificationsPrompt,
            !services.hasSeenWelcomeTour,
            !services.hasConfiguredTabBarPrompt,
        ]
    }

    /// Steps still to complete, including the current one.
    private var remainingOnboardingSteps: Int {
        onboardingPendingFlags.filter { $0 }.count
    }

    /// Total steps in this user's journey — the snapshot taken at sign-in, or the
    /// live remaining count before the snapshot lands.
    private var onboardingTotal: Int {
        onboardingTotalSnapshot ?? remainingOnboardingSteps
    }

    /// Current step (1-based) within the journey, or nil once onboarding is done.
    /// Numbered against the snapshotted total so it counts up (1→N) and never
    /// claims more steps than the user will see.
    private var onboardingStep: Int? {
        guard !services.authService.showsOnboarding else { return nil }
        let remaining = remainingOnboardingSteps
        guard remaining > 0 else { return nil }
        return max(1, onboardingTotal - remaining + 1)
    }
}

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

    var body: some View {
        Group {
            if services.authService.showsOnboarding {
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
            } else {
                MainTabView()
                    .transition(hasAppeared ? .opacity : .identity)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let onboardingStep = onboardingStep {
                let onboardingTotal = 3
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
                                .accessibilityLabel(progressAccessibilityLabel)
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
        .animation(hasAppeared ? .snappy(duration: 0.3) : nil, value: services.authService.showsOnboarding)
        .animation(hasAppeared ? .snappy(duration: 0.3) : nil, value: services.hasConfiguredRemindersPrompt)
        .animation(hasAppeared ? .snappy(duration: 0.3) : nil, value: services.hasConfiguredGmailPrompt)
        .animation(hasAppeared ? .snappy(duration: 0.3) : nil, value: services.hasConfiguredNotificationsPrompt)
        .animation(hasAppeared ? .snappy(duration: 0.3) : nil, value: services.hasConfiguredDefaultMailPrompt)
        .animation(hasAppeared ? .snappy(duration: 0.3) : nil, value: services.authService.isAuthenticated)
        .onAppear {
            // Enable transitions only after the first frame renders.
            // DispatchQueue.main.async ensures SwiftUI has committed the initial layout.
            DispatchQueue.main.async { hasAppeared = true }
        }
        .task {
            guard !hasRunDeferredStartup else { return }
            hasRunDeferredStartup = true
            await runDeferredStartupWork()
        }
        .task(id: services.authService.isAuthenticated) {
            guard services.authService.isAuthenticated else { return }
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
        await services.authService.fetchUserProfile()
        await services.loadSharedAIProfile()

        // Delay legacy upgrade work until after the initial shell is usable.
        try? await Task.sleep(for: .milliseconds(150))
        await services.completeAuthUpgradeIfNeeded(in: modelContext)
    }

    private var onboardingStep: Int? {
        guard !services.authService.showsOnboarding else { return nil }
        if !services.hasConfiguredGmailPrompt { return 1 }
        if !services.hasConfiguredRemindersPrompt { return 2 }
        if !services.hasConfiguredNotificationsPrompt { return 3 }
        return nil
    }
}

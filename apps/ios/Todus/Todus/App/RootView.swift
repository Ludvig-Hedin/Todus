import SwiftUI
import SwiftData

/// Root view — routes between auth, onboarding, and the main tab shell.
/// Uses the new AuthService (Better-Auth) for authentication state.
struct RootView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if services.authService.showsOnboarding {
                // Step 0: Not authenticated → sign in
                AuthView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if !services.hasConfiguredGmailPrompt {
                // Step 1: Gmail first — email is the primary value proposition,
                // so users should connect it before being asked about Reminders.
                GmailOnboardingView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if !services.hasConfiguredRemindersPrompt {
                // Step 2: Reminders sync — secondary power-user feature after core email setup.
                RemindersOnboardingView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                // All onboarding done → show the main app
                MainTabView()
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .animation(.snappy(duration: 0.3), value: services.authService.showsOnboarding)
        .animation(.snappy(duration: 0.3), value: services.hasConfiguredRemindersPrompt)
        .animation(.snappy(duration: 0.3), value: services.hasConfiguredGmailPrompt)
        .animation(.snappy(duration: 0.3), value: services.authService.isAuthenticated)
        .task {
            // Legacy auth upgrade — runs in background, doesn't block reminders setup
            await services.completeAuthUpgradeIfNeeded(in: modelContext)
        }
        .task {
            // Reminders setup — runs concurrently with auth upgrade via separate .task
            if await services.requestRemindersPermissionIfNeeded() {
                services.syncExistingTasksToReminders(in: modelContext)
                await services.importFromReminders(in: modelContext)
            }
        }
    }
}

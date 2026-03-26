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
                // Not authenticated and hasn't dismissed onboarding → show sign in
                AuthView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if !services.hasConfiguredRemindersPrompt {
                // Shown once after sign-up — lets the user opt in to Reminders sync
                RemindersOnboardingView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                // Authenticated or skipped → show the unified tab shell
                MainTabView()
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .animation(.snappy(duration: 0.3), value: services.authService.showsOnboarding)
        .animation(.snappy(duration: 0.3), value: services.hasConfiguredRemindersPrompt)
        .animation(.snappy(duration: 0.3), value: services.authService.isAuthenticated)
        .task {
            // Legacy auth upgrade — runs in background, doesn't block UI
            await services.completeAuthUpgradeIfNeeded(in: modelContext)

            if await services.requestRemindersPermissionIfNeeded() {
                services.syncExistingTasksToReminders(in: modelContext)
                await services.importFromReminders(in: modelContext)
            }
        }
    }
}

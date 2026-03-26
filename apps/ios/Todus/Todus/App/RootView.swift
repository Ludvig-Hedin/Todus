import OSLog
import SwiftUI
import SwiftData

private let startupLog = Logger(subsystem: "com.todus.startup", category: "rootview")

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
            let t0 = Date()
            startupLog.info("⏱ RootView .task begin (auth + reminders)")
            AppLogger.shared.log("⏱ RootView .task begin (auth + reminders)")

            // Legacy auth upgrade — will be removed once fully migrated
            let t1 = Date()
            await services.completeAuthUpgradeIfNeeded(in: modelContext)
            let authUpgradeTime = Date().timeIntervalSince(t1) * 1000
            startupLog.info("⏱ completeAuthUpgradeIfNeeded: \(authUpgradeTime, format: .fixed(precision: 1))ms")
            AppLogger.shared.log("⏱ completeAuthUpgradeIfNeeded: \(String(format: "%.1f", authUpgradeTime))ms")

            let t2 = Date()
            if await services.requestRemindersPermissionIfNeeded() {
                let remindersTime = Date().timeIntervalSince(t2) * 1000
                startupLog.info("⏱ requestRemindersPermission granted: \(remindersTime, format: .fixed(precision: 1))ms — syncing + importing")
                AppLogger.shared.log("⏱ requestRemindersPermission granted: \(String(format: "%.1f", remindersTime))ms — syncing + importing")
                services.syncExistingTasksToReminders(in: modelContext)
                await services.importFromReminders(in: modelContext)
            } else {
                let remindersTime = Date().timeIntervalSince(t2) * 1000
                startupLog.info("⏱ requestRemindersPermission skipped/denied: \(remindersTime, format: .fixed(precision: 1))ms")
                AppLogger.shared.log("⏱ requestRemindersPermission skipped/denied: \(String(format: "%.1f", remindersTime))ms")
            }

            let totalTime = Date().timeIntervalSince(t0) * 1000
            startupLog.info("⏱ RootView .task TOTAL: \(totalTime, format: .fixed(precision: 1))ms")
            AppLogger.shared.log("⏱ RootView .task TOTAL: \(String(format: "%.1f", totalTime))ms")
        }
    }
}

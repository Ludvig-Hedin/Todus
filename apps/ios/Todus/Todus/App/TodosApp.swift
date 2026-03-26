import OSLog
import SwiftUI
import SwiftData

private let startupLog = Logger(subsystem: "com.todus.startup", category: "app")

@main
struct TodosApp: App {
    @State private var services = AppServices()
    private let modelContainer: ModelContainer

    init() {
        let t0 = Date()
        startupLog.info("⏱ TodosApp.init() begin")
        AppLogger.shared.log("⏱ TodosApp.init() begin")

        let schema = Schema([
            TaskRecord.self,
            FolderRecord.self
        ])

        let t1 = Date()
        do {
            modelContainer = try ModelContainer(for: schema)
        } catch {
            let fallbackURL = FileManager.default.temporaryDirectory.appendingPathComponent("TodosFallback.store")
            let fallbackConfiguration = ModelConfiguration(url: fallbackURL, allowsSave: true)
            do {
                modelContainer = try ModelContainer(for: schema, configurations: fallbackConfiguration)
            } catch {
                fatalError("Failed to create model container: \(error)")
            }
        }
        let containerTime = Date().timeIntervalSince(t1) * 1000
        startupLog.info("⏱ ModelContainer: \(containerTime, format: .fixed(precision: 1))ms")
        AppLogger.shared.log("⏱ ModelContainer: \(String(format: "%.1f", containerTime))ms")
        let totalTime = Date().timeIntervalSince(t0) * 1000
        startupLog.info("⏱ TodosApp.init() TOTAL: \(totalTime, format: .fixed(precision: 1))ms")
        AppLogger.shared.log("⏱ TodosApp.init() TOTAL: \(String(format: "%.1f", totalTime))ms")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services)
                .modelContainer(modelContainer)
                .onOpenURL { url in
                    // Route deep links (todus://auth-callback?token=...) to new AuthService
                    services.authService.handleAuthCallback(url: url)
                    // Legacy handler — will be removed once migration is complete
                    services.authStore.handleIncomingAuthCallback(url: url)
                }
                .tint(AppTheme.accent)
                .preferredColorScheme(services.appearancePreference.colorScheme)
        }
    }
}

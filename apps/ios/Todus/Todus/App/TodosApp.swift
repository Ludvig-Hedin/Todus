import SwiftUI
import SwiftData

@main
struct TodosApp: App {
    @State private var services = AppServices()
    private let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            TaskRecord.self,
            FolderRecord.self
        ])

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

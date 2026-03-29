import SwiftUI
import SwiftData

@main
struct TodusMacApp: App {
    @State private var services = MacAppServices()

    var body: some Scene {
        WindowGroup {
            MacRootView()
                .environment(services)
                .environment(services.authService)
                .frame(minWidth: 1100, minHeight: 720)
                // Handle todus://auth-callback?token=... deep links from Google OAuth
                .onOpenURL { url in
                    services.authService.handleAuthCallback(url: url)
                }
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentSize)
        // Standard unified toolbar — proper button sizing
        .windowToolbarStyle(.unified)
        // SwiftData container for local task/folder persistence
        .modelContainer(for: [TaskRecord.self, FolderRecord.self])
    }
}

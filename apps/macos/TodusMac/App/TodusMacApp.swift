import SwiftUI
import SwiftData

@main
struct TodusMacApp: App {
    @State private var services = MacAppServices()
    private let sharedModelContainer: ModelContainer = {
        let schema = Schema([TaskRecord.self, FolderRecord.self])
        do {
            return try ModelContainer(for: schema)
        } catch {
            fatalError("Failed to create shared ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MacRootView()
                .environment(services)
                .environment(services.authService)
                .modelContainer(sharedModelContainer)
                .frame(minWidth: 1100, minHeight: 720)
                // Handle todus://auth-callback?token=... deep links from Google OAuth
                .onOpenURL { url in
                    services.authService.handleAuthCallback(url: url)
                }
                // Darken the window chrome (title bar / toolbar) to match the content area.
                // Without this, the unified toolbar background is lighter than the detail pane
                // in dark mode — creating a visible mismatch.
                .onAppear { setWindowBackgroundColor() }
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentSize)
        // Standard unified toolbar — proper button sizing
        .windowToolbarStyle(.unified)

        // Dedicated Settings window — opened via openWindow(id: "settings")
        // Stays open independently so the user can adjust prefs while using the app.
        Window("Settings", id: "settings") {
            MacSettingsView()
                .environment(services)
                .environment(services.authService)
                .modelContainer(sharedModelContainer)
                .frame(minWidth: 760, idealWidth: 760, maxWidth: 900)
                .frame(minHeight: 480, idealHeight: 640, maxHeight: .infinity)
                .onAppear { setWindowBackgroundColor() }
        }
        .defaultSize(width: 760, height: 640)
        .windowResizability(.contentSize)
    }

    /// Makes the window title bar / toolbar chrome match the content background.
    /// Sets both backgroundColor (fallback fill) and titlebar transparency so
    /// the SwiftUI content background bleeds all the way to the top edge.
    private func setWindowBackgroundColor() {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first else { return }
            window.backgroundColor = NSColor(MacTheme.contentBackground)
            window.titlebarAppearsTransparent = true
        }
    }
}

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
                .onAppear {
                    MacScrollStyle.install()
                    setWindowBackgroundColor()
                    // AppKit's NSWindow autosave persists frame across launches — write the
                    // name programmatically because SwiftUI's WindowGroup doesn't expose a
                    // first-class modifier for it on macOS 14. Pick the window backing the
                    // main scene (the one that is currently key, or the first non-Settings
                    // window) so we don't accidentally tag the Settings window instead.
                    DispatchQueue.main.async {
                        let candidate = NSApplication.shared.keyWindow
                            ?? NSApplication.shared.windows.first { $0.identifier?.rawValue.contains("Settings") != true }
                            ?? NSApplication.shared.windows.first
                        candidate?.setFrameAutosaveName("TodusMacMainWindow")
                    }
                }
        }
        .defaultSize(width: 1280, height: 820)
        .defaultPosition(.center)
        .windowResizability(.contentSize)
        // Standard unified toolbar — proper button sizing
        .windowToolbarStyle(.unified)
        .commands {
            // ⌘W — close the active window. WindowGroup binds this by default on most
            // macOS versions, but we replace the SaveItem group's standard items with an
            // explicit Close binding so the shortcut works even when no menu surface is
            // visible (e.g. after focus changes).
            CommandGroup(replacing: .saveItem) {
                Button("Close Window") {
                    NSApplication.shared.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }
            // ⌘Q — quit the app. Replace the default app-termination group so we can
            // bind a single, explicit shortcut without the system's localized fallbacks.
            CommandGroup(replacing: .appTermination) {
                Button("Quit Todus") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }

        // Dedicated Settings window — opened via openWindow(id: "settings")
        // Stays open independently so the user can adjust prefs while using the app.
        Window("Settings", id: "settings") {
            MacSettingsView()
                .focusEffectDisabled()
                .environment(services)
                .environment(services.authService)
                .modelContainer(sharedModelContainer)
                .frame(minWidth: 760, idealWidth: 760, maxWidth: 900)
                .frame(minHeight: 480, idealHeight: 640, maxHeight: .infinity)
                .onAppear {
                    MacScrollStyle.install()
                    setWindowBackgroundColor()
                    // Persist the Settings window frame independently of the main window.
                    DispatchQueue.main.async {
                        if let window = NSApplication.shared.keyWindow {
                            window.setFrameAutosaveName("TodusMacSettingsWindow")
                        }
                    }
                }
        }
        .defaultSize(width: 760, height: 640)
        .defaultPosition(.center)
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

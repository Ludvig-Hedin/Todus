import AppKit
import SwiftUI
import SwiftData

@main
struct TodusMacApp: App {
    @State private var services = MacAppServices()
    @Environment(\.scenePhase) private var scenePhase
    /// Deferred — populated by an off-main `Task` so the first frame isn't blocked on
    /// SwiftData schema migrations + persistent-store open (can take seconds on cold launch).
    /// While nil, the splash view renders. `modelContainerFailed` flips to true if every
    /// fallback (default → file → in-memory) raises, which renders a recoverable error UI.
    @State private var sharedModelContainer: ModelContainer?
    @State private var modelContainerFailed: Bool = false

    init() {
        // Bump shared URLCache so AsyncImage's downloaded avatar bytes survive memory
        // pressure and persist across launches. The default 4MB/20MB is too small for
        // an inbox of senders; this gives ~250MB on disk for image data.
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 250 * 1024 * 1024,
            diskPath: "todus-url-cache"
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if modelContainerFailed {
                    modelContainerErrorView
                } else if let sharedModelContainer {
                    MacRootView()
                        .environment(services)
                        .environment(services.authService)
                        .modelContainer(sharedModelContainer)
                        .frame(minWidth: 1100, minHeight: 720)
                        // Handle todus://auth-callback and mailto: deep links
                        .onOpenURL { url in
                            // RFC 3986: URL schemes are case-insensitive — normalize so MAILTO:/Mailto:
                            // links don't fall through to the auth callback handler.
                            if url.scheme?.lowercased() == "mailto" {
                                handleMailtoURL(url, services: services)
                            } else {
                                services.authService.handleAuthCallback(url: url)
                            }
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
                        .onChange(of: scenePhase) { oldPhase, newPhase in
                            if newPhase == .background {
                                Task {
                                    await MacWidgetUpdateManager.shared.updateWidgets(
                                        context: sharedModelContainer.mainContext,
                                        emailService: services.emailService
                                    )
                                }
                            }
                        }
                } else {
                    splashView
                        .task { await initializeApp() }
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

        // Detached AI Assistant window — opened via openWindow(id: "ai-chat") when the user
        // selects "Separate Window" from the panel layout picker.
        // Uses .hiddenTitleBar + isMovableByWindowBackground so the panel header acts as the
        // drag handle, exactly like the floating overlay — but in a real NSWindow.
        Window("AI Assistant", id: "ai-chat") {
            Group {
                if modelContainerFailed {
                    modelContainerErrorView
                } else if let sharedModelContainer {
                    AIChatWindowContent()
                        .environment(services)
                        .environment(services.authService)
                        .modelContainer(sharedModelContainer)
                } else {
                    splashView
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 400, height: 560)
        .defaultPosition(.topTrailing)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        // Dedicated Settings window — opened via openWindow(id: "settings")
        // Stays open independently so the user can adjust prefs while using the app.
        Window("Settings", id: "settings") {
            Group {
                if modelContainerFailed {
                    modelContainerErrorView
                } else if let sharedModelContainer {
                    MacSettingsView()
                        .focusEffectDisabled()
                        .environment(services)
                        .environment(services.authService)
                        .modelContainer(sharedModelContainer)
                } else {
                    splashView
                }
            }
            .frame(minWidth: 760, idealWidth: 760, maxWidth: 900)
            .frame(minHeight: 480, idealHeight: 640, maxHeight: .infinity)
            .onAppear {
                MacScrollStyle.install()
                setWindowBackgroundColor()
                // Persist the Settings window frame — avoid keyWindow (may be main or another).
                DispatchQueue.main.async {
                    let w = NSApplication.shared.windows.first { win in
                        win.title == "Settings" || (win.identifier?.rawValue).map { $0.contains("settings") } == true
                    }
                    w?.setFrameAutosaveName("TodusMacSettingsWindow")
                }
            }
        }
        .defaultSize(width: 760, height: 640)
        .defaultPosition(.center)
        .windowResizability(.contentSize)
        // Auxiliary window: do not auto-present or restore at launch. Otherwise a
        // previously-open Settings window reappears while the main scene shows sign-in.
        .defaultLaunchBehavior(.suppressed)
    }

    /// Creates `ModelContainer` off the synchronous init path. The splash screen is visible
    /// while this runs, eliminating the multi-second blank-window stall on cold launch.
    @MainActor
    private func initializeApp() async {
        let schema = Schema([TaskRecord.self, FolderRecord.self, FolderItemRecord.self, DraftRecord.self])

        let result: ContainerInitResult = await Task.detached(priority: .userInitiated) {
            do {
                return .success(try ModelContainer(for: schema))
            } catch {
                let fileManager = FileManager.default
                let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    ?? fileManager.temporaryDirectory
                if !fileManager.fileExists(atPath: appSupportDir.path) {
                    try? fileManager.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
                }
                let fallbackURL = appSupportDir.appendingPathComponent("TodusMacFallback.store")
                let fallbackConfiguration = ModelConfiguration(url: fallbackURL, allowsSave: true)
                do {
                    return .success(try ModelContainer(for: schema, configurations: fallbackConfiguration))
                } catch {
                    let inMemoryConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                    do {
                        return .success(try ModelContainer(for: schema, configurations: inMemoryConfig))
                    } catch {
                        return .failed
                    }
                }
            }
        }.value

        await Task.yield()

        switch result {
        case .success(let container):
            self.sharedModelContainer = container
            services.modelContainer = container
            services.setupNetworkSync()
        case .failed:
            self.modelContainerFailed = true
        }
    }

    /// Branded splash shown while `ModelContainer` initializes. Renders within one frame
    /// so the user never sees a blank window on cold launch.
    private var splashView: some View {
        ZStack {
            MacTheme.contentBackground.ignoresSafeArea()
            VStack(spacing: 20) {
                Image("BrandLogo")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(.primary.opacity(0.8))
                    .frame(width: 56, height: 56)
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    /// Recoverable error UI shown when no `ModelContainer` (file or in-memory) can be created.
    private var modelContainerErrorView: some View {
        ZStack {
            MacTheme.contentBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
                Text("Couldn't initialize local data")
                    .font(.system(size: 18, weight: .semibold))
                Text("Todus could not create a local data store on this device. Please reinstall the app to recover.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
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

/// Result of the off-main `ModelContainer` initialization chain. `ModelContainer` is
/// `Sendable`, so it can cross the actor boundary back to MainActor.
private enum ContainerInitResult: Sendable {
    case success(ModelContainer)
    case failed
}

// MARK: - AI Chat Window Content

/// Content for the detached "ai-chat" Window scene. Shares `MacAIChatService` via
/// `MacAppServices` in the environment, so conversation state is consistent with the
/// floating/sidepane modes. When the user switches back to floating or side layout the
/// window dismisses itself and MacRootView re-opens the panel inline.
private struct AIChatWindowContent: View {
    @Environment(MacAppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mac_assistant_display_mode") private var displayModeRaw: String = AssistantDisplayMode.window.rawValue

    @State private var geo = FloatingPanelGeometry()

    private var displayModeBinding: Binding<AssistantDisplayMode> {
        Binding(
            get: { AssistantDisplayMode(rawValue: displayModeRaw) ?? .window },
            set: { newMode in
                displayModeRaw = newMode.rawValue
                if newMode != .window { dismiss() }
            }
        )
    }

    var body: some View {
        MacAssistantPanel(
            isPresented: Binding(
                get: { true },
                set: { if !$0 { displayModeRaw = AssistantDisplayMode.floating.rawValue; dismiss() } }
            ),
            displayMode: displayModeBinding,
            geo: geo,
            currentSelection: .home
        )
        .background(WindowMovableBackground())
        .onDisappear {
            if displayModeRaw == AssistantDisplayMode.window.rawValue {
                displayModeRaw = AssistantDisplayMode.floating.rawValue
            }
        }
    }
}

/// Makes the host NSWindow movable by clicking on non-interactive background areas —
/// mirrors the floating panel's drag-by-header behaviour in the detached window.
private struct WindowMovableBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.isMovableByWindowBackground = true
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Parse a `mailto:` URL and store the fields in `MacAppServices` so `MacRootView`
/// can open the compose panel with pre-filled recipient, subject, and body.
@MainActor
private func handleMailtoURL(_ url: URL, services: MacAppServices) {
    var to = url.path
    var subject: String? = nil
    var body: String? = nil

    if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
        for item in components.queryItems ?? [] {
            switch item.name.lowercased() {
            case "to":
                if let v = item.value, !v.isEmpty {
                    to = [to, v].filter { !$0.isEmpty }.joined(separator: ",")
                }
            case "subject": subject = item.value
            case "body":    body = item.value
            default: break
            }
        }
    }

    let normalized = MacAppServices.PendingMailto(
        to: to.isEmpty ? nil : to,
        subject: (subject == nil || subject?.isEmpty == true) ? nil : subject,
        body: (body == nil || body?.isEmpty == true) ? nil : body
    )
    guard normalized.to != nil || normalized.subject != nil || normalized.body != nil else { return }
    services.pendingMailto = normalized
}

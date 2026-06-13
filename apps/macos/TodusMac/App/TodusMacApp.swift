import AppKit
import SwiftUI
import SwiftData
import UserNotifications

@main
struct TodusMacApp: App {
    @State private var services = MacAppServices()
    @Environment(\.scenePhase) private var scenePhase
    /// AppDelegate is required for `UNUserNotificationCenterDelegate` so notification
    /// taps + actions (complete, snooze, archive) route while the app is running.
    /// Wired into `services` after `initializeApp()` finishes so action handlers can
    /// reach SwiftData + the email/task services.
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    /// Deferred — populated by an off-main `Task` so the first frame isn't blocked on
    /// SwiftData schema migrations + persistent-store open (can take seconds on cold launch).
    /// While nil, the splash view renders. `modelContainerFailed` flips to true if every
    /// fallback (default → file → in-memory) raises, which renders a recoverable error UI.
    @State private var sharedModelContainer: ModelContainer?
    @State private var modelContainerFailed: Bool = false
    /// Deep-link URLs that arrived before `sharedModelContainer` / services were ready.
    /// Replayed in order once initialization completes so we don't drop auth callbacks
    /// or `mailto:` links sent during the splash-screen window. Cleared after replay.
    @State private var pendingDeepLinks: [URL] = []

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
                            handleIncomingURL(url)
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
                            // Refresh widgets on .inactive too — a windowed macOS
                            // app rarely reaches .background (only when all windows
                            // close), so .background-only left widgets stale on every
                            // focus change.
                            if newPhase == .background || newPhase == .inactive {
                                Task {
                                    MacWidgetUpdateManager.shared.updateWidgets(
                                        context: sharedModelContainer.mainContext,
                                        services: services
                                    )
                                }
                            } else if newPhase == .active {
                                // Push any mutations queued while inactive/offline,
                                // and apply widget-tapped task completions.
                                services.flushPendingSync()
                                services.drainWidgetTaskCompletions()
                                // Re-arm task reminders + refresh the due-today digest in
                                // case tasks changed (or the day rolled over) while inactive.
                                services.reconcileTaskReminders()
                            }
                        }
                } else {
                    splashView
                        .task { await initializeApp() }
                        // Capture deep links that arrive before services are wired.
                        // They're queued and replayed in `initializeApp()`.
                        .onOpenURL { url in
                            handleIncomingURL(url)
                        }
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
            // Flush any task/folder/draft mutations left `.pendingUpload` from a
            // previous online session (they used to wait for a reconnect event
            // that never comes if the user is already online).
            services.flushPendingSync()
            // Apply any task completions tapped on a widget while the app was closed.
            services.drainWidgetTaskCompletions()
            // Reconcile local task reminders + due-today digest against the loaded task
            // set (the toggles previously persisted but scheduled nothing).
            services.reconcileTaskReminders()
            // Wire the delegate so UNUserNotificationCenter callbacks can resolve tasks
            // (SwiftData) and reach email/AI services for routing + actions.
            appDelegate.modelContainer = container
            appDelegate.services = services
            UNUserNotificationCenter.current().delegate = appDelegate
            // Replay any notification taps that arrived during cold launch before the
            // delegate's services/container were wired (mirrors pendingDeepLinks below).
            appDelegate.replayPendingNotificationResponses()
            // Wire SwiftData into the voice coordinator so tool calls
            // (create_task etc.) have a context to mutate. Without this,
            // voice tools fall back to a friendly "open the chat panel
            // first" error.
            services.voiceCoordinator.modelContext = container.mainContext
            // Apply the user's saved voice prefs after the container is
            // ready so we never start the hotkey before the chat service
            // can actually handle a tool call.
            services.applyVoiceAssistantState()
            // Replay any deep links that arrived before init completed.
            if !pendingDeepLinks.isEmpty {
                let queued = pendingDeepLinks
                pendingDeepLinks = []
                for url in queued {
                    dispatchValidatedURL(url)
                }
            }
        case .failed:
            self.modelContainerFailed = true
        }
    }

    /// Validates and dispatches incoming deep links. Reject hosts other than the
    /// expected `auth-callback` (for `todus://` schemes) to prevent untrusted apps
    /// from injecting URLs that flow into the auth handler. If services are not yet
    /// ready (cold launch + immediate deep link), queue the URL and replay after init.
    @MainActor
    private func handleIncomingURL(_ url: URL) {
        // mailto: links — always safe to hand to the compose handler. RFC 3986:
        // schemes are case-insensitive, normalize so MAILTO:/Mailto: don't slip
        // through to the auth callback branch.
        if url.scheme?.lowercased() == "mailto" {
            if sharedModelContainer == nil {
                pendingDeepLinks.append(url)
            } else {
                handleMailtoURL(url, services: services)
            }
            return
        }

        // Defer non-ready URLs so they're not silently dropped during cold launch.
        if sharedModelContainer == nil {
            pendingDeepLinks.append(url)
            return
        }

        dispatchValidatedURL(url)
    }

    /// Dispatch path used after services are confirmed ready. Mirrors `handleIncomingURL`
    /// but assumes the container is initialized — used both directly and by the queued
    /// replay loop.
    @MainActor
    private func dispatchValidatedURL(_ url: URL) {
        if url.scheme?.lowercased() == "mailto" {
            handleMailtoURL(url, services: services)
            return
        }

        // Route `todus://` URLs by host. Only known hosts are accepted so an
        // attacker-controlled URL (e.g. `todus://malicious`) cannot inject into
        // the auth-callback state machine.
        switch url.host?.lowercased() {
        case "auth-callback":
            // AuthService already enforces an in-flight `pendingAuthFlowExpiresAt`
            // provenance window and rejects unsolicited auth-callback URLs that arrive
            // while a user is already authenticated. We rely on that as the second
            // layer of defense against an attacker-controlled token injection.
            services.authService.handleAuthCallback(url: url)

        case "share":
            // `todus://share?slug=abc123` — open the shared AI conversation viewer.
            // Slug is broadcast over NotificationCenter so any presenter (MacRootView
            // or a sibling sheet) can react without requiring a new state field on
            // MacAppServices (which is owned by another agent).
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let slug = components.queryItems?.first(where: { $0.name == "slug" })?.value,
               !slug.isEmpty {
                NotificationCenter.default.post(
                    name: .todusOpenSharedConversation,
                    object: slug
                )
            }

        case "tasks", "today":
            // Widget deep links (`todus://tasks`, `todus://today`). Navigation
            // only — just selects the view, so there's no injection surface.
            NotificationCenter.default.post(name: .todusNavigateToTasks, object: nil)

        case "email":
            // Widget deep link (`todus://email/inbox`).
            NotificationCenter.default.post(name: .todusNavigateToEmail, object: nil)

        default:
            // Silently ignore — unknown host, not something we recognize.
            return
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
        .focusEffectDisabled()
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

/// Sendable snapshot of a notification's text fields captured on the nonisolated
/// delegate callback so we can rebuild a `UNMutableNotificationContent` on the
/// MainActor without sending the non-Sendable original across actors. Mirrors the
/// iOS implementation in `TodosApp.swift`.
private struct MacSnoozeContentSnapshot: Sendable {
    let title: String
    let subtitle: String
    let body: String
    let categoryIdentifier: String
    let threadIdentifier: String
    let badge: Int?
}

/// Sendable snapshot of a tapped notification response. Captured on the nonisolated
/// delegate callback so a cold-launch tap (services/modelContainer still nil) can be
/// queued and replayed once `initializeApp()` wires the services — mirroring the
/// `pendingDeepLinks` mechanism for `todus://` / `mailto:` URLs.
fileprivate struct MacNotificationResponseSnapshot: Sendable {
    let taskIDString: String
    let threadIdString: String?
    let conversationIdString: String?
    let categoryIdentifier: String
    let actionIdentifier: String
    let requestIdentifier: String
    let snoozeSnapshot: MacSnoozeContentSnapshot?

    /// True when routing this response needs the wired `services` / `modelContainer`
    /// (everything except the self-contained snooze re-schedule). A cold-launch tap of
    /// one of these must be queued rather than dropped.
    var requiresServices: Bool {
        actionIdentifier != MacNotificationService.Action.snooze
    }
}

// MARK: - MacAppDelegate (Notification Action Handling)

/// Handles `UNUserNotificationCenter` foreground presentation + tap/action routing for
/// the macOS app. Mirrors the iOS `AppDelegate` in `TodosApp.swift` so the same payload
/// shapes (`taskID`, `threadId`, `conversationId`) route identically on both platforms.
///
/// Routing for surfaces this delegate can't directly mutate (the active main view's
/// navigation selection lives in `MacRootView` `@State`) is published over
/// `NotificationCenter` so any view can observe and react without coupling.
@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    /// Provided by `TodusMacApp.initializeApp()` once SwiftData is ready. Until then,
    /// notification actions that need a `ModelContext` (Complete) are no-ops.
    var modelContainer: ModelContainer?
    /// Weak reference so the delegate doesn't extend `MacAppServices` lifetime.
    weak var services: MacAppServices?

    /// Notification taps that arrived during cold launch before `services` /
    /// `modelContainer` were wired. Queued here and replayed by
    /// `replayPendingNotificationResponses()` at the end of `initializeApp()` so a tap
    /// that launches the app from cold isn't silently dropped (mirrors `pendingDeepLinks`).
    private var pendingNotificationResponses: [MacNotificationResponseSnapshot] = []

    /// Replays any notification taps queued during cold launch. Called once after
    /// `services` + `modelContainer` are set in `initializeApp()`.
    func replayPendingNotificationResponses() {
        guard !pendingNotificationResponses.isEmpty else { return }
        let queued = pendingNotificationResponses
        pendingNotificationResponses = []
        for snapshot in queued {
            route(snapshot)
        }
    }

    /// Queue a response for later replay (services not ready yet).
    fileprivate func enqueuePendingNotificationResponse(_ snapshot: MacNotificationResponseSnapshot) {
        pendingNotificationResponses.append(snapshot)
    }
}

extension MacAppDelegate: UNUserNotificationCenterDelegate {
    /// Present banners + sound while the app is foregrounded so notifications aren't
    /// silently swallowed when the user is actively using Todus.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Snapshot Sendable primitives BEFORE hopping to the MainActor — the original
        // `UNNotificationResponse` / userInfo dictionary are not Sendable.
        let userInfo = response.notification.request.content.userInfo
        let taskIDString = userInfo["taskID"] as? String ?? ""
        let threadIdString = userInfo["threadId"] as? String
        let conversationIdString = userInfo["conversationId"] as? String
        let categoryIdentifier = response.notification.request.content.categoryIdentifier
        let actionIdentifier = response.actionIdentifier
        let requestIdentifier = response.notification.request.identifier

        let snoozeSnapshot: MacSnoozeContentSnapshot? = {
            guard actionIdentifier == MacNotificationService.Action.snooze else { return nil }
            let c = response.notification.request.content
            return MacSnoozeContentSnapshot(
                title: c.title,
                subtitle: c.subtitle,
                body: c.body,
                categoryIdentifier: c.categoryIdentifier,
                threadIdentifier: c.threadIdentifier,
                badge: c.badge?.intValue
            )
        }()

        let snapshot = MacNotificationResponseSnapshot(
            taskIDString: taskIDString,
            threadIdString: threadIdString,
            conversationIdString: conversationIdString,
            categoryIdentifier: categoryIdentifier,
            actionIdentifier: actionIdentifier,
            requestIdentifier: requestIdentifier,
            snoozeSnapshot: snoozeSnapshot
        )

        // Call completionHandler immediately on the nonisolated context so we don't
        // capture an `@escaping` handler in a MainActor Task (Sendability risk).
        completionHandler()

        Task { @MainActor in
            // Cold-launch tap: services/modelContainer not wired yet. Queue the
            // (Sendable) snapshot so `initializeApp()` can replay it once ready, rather
            // than dropping it on the floor. Self-contained actions (snooze) still run now.
            if snapshot.requiresServices, self.services == nil {
                self.enqueuePendingNotificationResponse(snapshot)
                return
            }
            self.route(snapshot)
        }
    }

    /// Routes a (possibly-replayed) notification response on the MainActor. Split out of
    /// `didReceive` so both the live path and the cold-launch replay path share identical
    /// routing logic.
    @MainActor
    fileprivate func route(_ snapshot: MacNotificationResponseSnapshot) {
        let taskIDString = snapshot.taskIDString
        let threadIdString = snapshot.threadIdString
        let conversationIdString = snapshot.conversationIdString
        let categoryIdentifier = snapshot.categoryIdentifier
        let actionIdentifier = snapshot.actionIdentifier
        let requestIdentifier = snapshot.requestIdentifier
        let snoozeSnapshot = snapshot.snoozeSnapshot

        Task { @MainActor in
            switch actionIdentifier {
            case MacNotificationService.Action.complete:
                // Mark the task complete via SwiftData.
                guard let container = self.modelContainer,
                      let taskID = UUID(uuidString: taskIDString) else { return }
                let context = container.mainContext
                let descriptor = FetchDescriptor<TaskRecord>(
                    predicate: #Predicate { task in task.id == taskID }
                )
                if let task = (try? context.fetch(descriptor))?.first {
                    task.completed = true
                    task.status = .done
                    task.updatedAt = .now
                    try? context.save()
                    // Broadcast for any listeners (sync services, UI refreshers) so the
                    // mutation propagates beyond the delegate context.
                    NotificationCenter.default.post(
                        name: .todusCompleteTask,
                        object: nil,
                        userInfo: ["taskID": taskIDString]
                    )
                }

            case MacNotificationService.Action.snooze:
                // Re-schedule the same notification 1 hour from now. Rebuild content
                // from the Sendable snapshot to avoid sending UNNotificationContent.
                guard let s = snoozeSnapshot else { break }
                let content = UNMutableNotificationContent()
                content.title = s.title
                content.subtitle = s.subtitle
                content.body = s.body
                if !taskIDString.isEmpty {
                    content.userInfo = ["taskID": taskIDString]
                }
                content.categoryIdentifier = s.categoryIdentifier
                content.threadIdentifier = s.threadIdentifier
                if let b = s.badge {
                    content.badge = NSNumber(value: b)
                }
                content.sound = .default

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
                let request = UNNotificationRequest(
                    identifier: requestIdentifier,
                    content: content,
                    trigger: trigger
                )
                try? await UNUserNotificationCenter.current().add(request)

            case MacNotificationService.Action.archiveEmail:
                // Archive the email thread via the existing EmailService API. Failures
                // surface inside EmailService (errorMessage on the service); no
                // additional UI prompt here since the notification has already gone.
                guard let services = self.services,
                      let threadId = threadIdString, !threadId.isEmpty else { return }
                await services.emailService.archiveThreads(ids: [threadId])

            default:
                // Default tap (`UNNotificationDefaultActionIdentifier`) — route based on
                // category + payload. Each branch publishes over NotificationCenter so
                // MacRootView (which owns the navigation `@State`) can react without
                // requiring new mutable surface on MacAppServices.
                guard let services = self.services else { return }

                switch categoryIdentifier {
                case MacNotificationService.Category.emailNotification,
                     MacNotificationService.Category.emailReminder:
                    if let threadId = threadIdString, !threadId.isEmpty {
                        NotificationCenter.default.post(
                            name: .todusOpenEmailThread,
                            object: threadId
                        )
                    } else {
                        NotificationCenter.default.post(name: .todusNavigateToEmail, object: nil)
                    }

                case MacNotificationService.Category.aiResponse:
                    // Open the AI assistant panel and load the specific conversation.
                    services.showsAssistantPanel = true
                    if let conversationId = conversationIdString, !conversationId.isEmpty {
                        NotificationCenter.default.post(
                            name: .todusOpenAIConversation,
                            object: nil,
                            userInfo: ["conversationId": conversationId]
                        )
                    }

                case MacNotificationService.Category.taskReminder,
                     MacNotificationService.Category.dueTasks:
                    NotificationCenter.default.post(
                        name: .todusNavigateToTasks,
                        object: taskIDString.isEmpty ? nil : taskIDString
                    )

                default:
                    // Unknown category — best-effort: if a threadId is present route to
                    // mail, if a conversationId is present route to AI, otherwise no-op.
                    if let threadId = threadIdString, !threadId.isEmpty {
                        NotificationCenter.default.post(name: .todusOpenEmailThread, object: threadId)
                    } else if let conversationId = conversationIdString, !conversationId.isEmpty {
                        services.showsAssistantPanel = true
                        NotificationCenter.default.post(
                            name: .todusOpenAIConversation,
                            object: nil,
                            userInfo: ["conversationId": conversationId]
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Notification routing channels

extension Notification.Name {
    /// Posted when the user taps a `todus://share?slug=...` deep link. The slug is
    /// passed as `object`. Observers (e.g. `MacRootView` or a sibling host view)
    /// should present `MacSharedConversationView(slug:)` as a sheet.
    static let todusOpenSharedConversation = Notification.Name("TodusOpenSharedConversation")

    /// Posted when the user taps an AI-response notification (default action).
    /// `userInfo["conversationId"]` carries the conversation to load.
    static let todusOpenAIConversation = Notification.Name("TodusOpenAIConversation")

    /// Posted when the user taps an email notification with a specific thread payload.
    /// `object` is the `String` thread id.
    static let todusOpenEmailThread = Notification.Name("TodusOpenEmailThread")

    /// Posted when a notification should switch the main view to email (no specific thread).
    static let todusNavigateToEmail = Notification.Name("TodusNavigateToEmail")

    /// Posted when a notification should switch the main view to tasks. `object` may
    /// optionally be a `String` task id to focus.
    static let todusNavigateToTasks = Notification.Name("TodusNavigateToTasks")

    /// Posted when a task-complete notification action fires. `userInfo["taskID"]`
    /// carries the completed task id (string UUID).
    static let todusCompleteTask = Notification.Name("TodusCompleteTask")
}

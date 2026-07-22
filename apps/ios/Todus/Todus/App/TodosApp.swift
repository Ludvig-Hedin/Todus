import SwiftUI
import SwiftData
import UIKit
import UserNotifications

@main
struct TodosApp: App {
    // Deferred initialization — services and model container are created AFTER the first
    // frame renders, so the user sees a branded splash instead of a 9+ second black screen.
    // Previously both were initialized synchronously in init(), blocking the main thread.
    @State private var services: AppServices?
    @State private var modelContainer: ModelContainer?
    /// Set true if every ModelContainer init path (default, fallback file, in-memory) fails.
    /// We render a non-crashing error view instead of `fatalError`'ing on launch.
    @State private var modelContainerFailed: Bool = false
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if modelContainerFailed {
                modelContainerErrorView
            } else if let services, let modelContainer {
                RootView()
                    .environment(services)
                    .modelContainer(modelContainer)
                    .task {
                        // Forward `--simulated-deep-link <url>` / `--simulated-notification <payload>`
                        // launch args into the same routing paths the real OpenURL / notification
                        // handlers use. Gated on `--ui-testing` so a missing/typo arg in production
                        // can't accidentally drive deep-link routing.
                        processUITestingLaunchArgs(services: services)
                    }
                    .onOpenURL { url in
                        handleIncomingURL(url, services: services)
                    }
                    .tint(AppTheme.accent)
                    .preferredColorScheme(services.appearancePreference.colorScheme)
                    .task(id: services.authService.isAuthenticated) {
                        // Subscribe once after AppServices is alive — the AppIntent
                        // posts `.todusStartVoiceSession` which we forward to the
                        // shared `VoiceSessionCoordinator`. Re-runs on auth flips so
                        // a session triggered before sign-in cleanly no-ops.
                        await subscribeToVoiceSessionStartTrigger(services: services)
                    }
                    .onChange(of: scenePhase) { oldPhase, newPhase in
                        if newPhase == .background {
                            AvatarCache.shared.flushPendingSaves()
                            let ctx = modelContainer.mainContext
                            let emailSvc = services.emailService
                            let calSvc = services.calendarService
                            Task {
                                await WidgetUpdateManager.shared.updateWidgets(
                                    context: ctx,
                                    emailService: emailSvc,
                                    calendarService: calSvc
                                )
                            }
                        }
                    }
            } else {
                // Lightweight splash — renders instantly while services initialize
                splashView
                    .task { await initializeApp() }
                    .onOpenURL { url in
                        // The production URL can arrive before ModelContainer/AppServices
                        // finish cold-starting. Preserve it and replay once routing exists.
                        appDelegate.pendingURL = url
                    }
            }
        }
    }

    /// Creates ModelContainer + AppServices off the synchronous init path.
    /// The splash screen is visible while this runs, eliminating the black screen.
    @MainActor
    private func initializeApp() async {
#if DEBUG
        MainThreadHangWatchdog.shared.start()
#endif
        let trace = PerformanceTrace.beginInterval(
            PerformanceTrace.initializeApp,
            message: "TodosApp.initializeApp begin"
        )
        defer {
            PerformanceTrace.endInterval(
                PerformanceTrace.initializeApp,
                trace,
                message: "TodosApp.initializeApp end"
            )
        }

        // Bump shared URLCache so AsyncImage's downloaded avatar bytes survive memory
        // pressure and persist across launches. The default 4MB/20MB is too small for
        // an inbox of senders; this gives ~250MB on disk for image data.
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 250 * 1024 * 1024,
            diskPath: "todus-url-cache"
        )

        let schema = Schema([TaskRecord.self, FolderRecord.self, FolderItemRecord.self, DraftRecord.self])

        // ModelContainer init runs schema migrations and opens the persistent store —
        // both can take multiple seconds on cold launch. Doing it on the MainActor
        // froze the splash for the duration of that work. Push the entire create-or-
        // fallback chain to a detached background task so the splash stays responsive.
        let result: ContainerInitResult = await Task.detached(priority: .userInitiated) {
            do {
                return .success(try ModelContainer(for: schema))
            } catch {
                AppLogger.shared.log(
                    "[TodosApp] ModelContainer default init failed: \(error.localizedDescription) — trying fallback file store"
                )
                let fileManager = FileManager.default
                let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    ?? fileManager.temporaryDirectory
                if !fileManager.fileExists(atPath: appSupportDir.path) {
                    try? fileManager.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
                }
                let fallbackURL = appSupportDir.appendingPathComponent("TodosFallback.store")
                let fallbackConfiguration = ModelConfiguration(url: fallbackURL, allowsSave: true)
                do {
                    return .success(try ModelContainer(for: schema, configurations: fallbackConfiguration))
                } catch {
                    AppLogger.shared.log(
                        "[TodosApp] ModelContainer fallback file store failed: \(error.localizedDescription) — trying in-memory store"
                    )
                    let inMemoryConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                    do {
                        return .success(try ModelContainer(for: schema, configurations: inMemoryConfig))
                    } catch {
                        AppLogger.shared.log(
                            "[TodosApp] ModelContainer in-memory init failed: \(error.localizedDescription) — rendering error UI"
                        )
                        return .failed
                    }
                }
            }
        }.value

        let container: ModelContainer
        switch result {
        case .success(let c):
            container = c
        case .failed:
            self.modelContainerFailed = true
            appDelegate.didFinishInitialization()
            return
        }

        // Yield to let the run loop process any pending UI work (keeps splash responsive)
        await Task.yield()

        // Pre-read Keychain auth tokens on a background thread so AppServices.init()
        // doesn't block the main thread with synchronous SecItemCopyMatching calls
        // (each can stall 300–800 ms on cold launch when the Keychain daemon is cold).
        let preloadedTokens = await Task.detached(priority: .userInitiated) {
            AuthService.preloadTokens()
        }.value

        // Assign container to appDelegate BEFORE setting @State so notification
        // actions can resolve tasks immediately — avoids race with onAppear.
        appDelegate.modelContainer = container

        let svc = AppServices(preloadedAuthTokens: preloadedTokens)
        // Wire AppServices into AppDelegate so notification-action failures (which run
        // outside SwiftUI environment) can surface a user-facing error state.
        appDelegate.services = svc

        svc.modelContainer = container
        svc.setupNetworkSync()

        self.modelContainer = container
        self.services = svc
        appDelegate.didFinishInitialization()
        if let pendingURL = appDelegate.pendingURL {
            appDelegate.pendingURL = nil
            handleIncomingURL(pendingURL, services: svc)
        }
    }

    /// Last-resort fallback shown when no `ModelContainer` (file or in-memory) can be created.
    /// Replaces a previous `fatalError` that crashed the app on launch — the user now sees a
    /// recoverable message and can reinstall instead of looking at a black screen / crash.
    private var modelContainerErrorView: some View {
        ZStack {
            AppTheme.backgroundTop.ignoresSafeArea()
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

    /// Branded splash screen shown during initialization — renders in < 1 frame.
    /// Minimal: just the Todus logomark centered on the app background.
    private var splashView: some View {
        ZStack {
            AppTheme.backgroundTop.ignoresSafeArea()

            VStack(spacing: 20) {
                Image("BrandLogo")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(.primary.opacity(0.8))
                    .frame(width: 56, height: 56)

                ProgressView()
                    .tint(.secondary.opacity(0.5))
                    .controlSize(.small)
            }
        }
    }
}

@MainActor
private func handleIncomingURL(_ url: URL, services: AppServices) {
    if url.scheme == "mailto" {
        handleMailtoURL(url, services: services)
        return
    }
    // Route todus:// links by host so non-auth deep links do not hit the auth
    // state machine and get interpreted as a failed sign-in.
    if url.scheme == "todus", let host = url.host {
        switch host {
        case "auth-callback", "link-callback":
            services.authService.handleAuthCallback(url: url)
            services.authStore.handleIncomingAuthCallback(url: url)
        default:
            break
        }
        return
    }
    services.authService.handleAuthCallback(url: url)
    services.authStore.handleIncomingAuthCallback(url: url)
}

/// Subscribe to the `.todusStartVoiceSession` notification posted by
/// `StartVoiceAssistantIntent`. Awaits the async-stream form so the
/// subscription naturally ends when the surrounding `.task` is cancelled
/// (i.e. when the user signs out and the WindowGroup body re-evaluates).
@MainActor
private func subscribeToVoiceSessionStartTrigger(services: AppServices) async {
    let center = NotificationCenter.default
    let stream = center.notifications(named: .todusStartVoiceSession).map { _ in () }
    for await _ in stream {
        // Hydrate the coordinator with a SwiftData context so write tools work.
        if services.voiceSessionCoordinator.modelContext == nil,
           let context = services.modelContainer?.mainContext {
            services.voiceSessionCoordinator.modelContext = context
        }
        await services.voiceSessionCoordinator.start()
    }
}

/// Parse a `mailto:` URL and open the email compose sheet with pre-filled fields.
/// Format: `mailto:to@example.com?subject=Hello&body=World`
@MainActor
private func handleMailtoURL(_ url: URL, services: AppServices) {
    // The recipient lives in the URL path ("to@example.com") or as a `to` query param.
    var to = url.path
    var subject: String? = nil
    var body: String? = nil

    if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
        for item in components.queryItems ?? [] {
            switch item.name.lowercased() {
            case "to":      if let v = item.value, !v.isEmpty { to = v }
            case "subject": subject = item.value
            case "body":    body = item.value
            default: break
            }
        }
    }

    services.composeEmailSeedTo = to.isEmpty ? nil : to
    services.composeEmailSeedSubject = subject
    services.composeEmailSeedBody = body
    services.showsComposeEmail = true
}

/// Bridges `--simulated-deep-link <url>` / `--simulated-notification <payload>`
/// launch arguments into the same routing entry points the live OpenURL and
/// notification handlers use. Only fires when `--ui-testing` is also present
/// so a stray argument in production builds is inert.
///
/// Notification payload syntax:
///   - `thread:<threadId>` → routes to the email tab + opens that thread
///   - `task:<uuid>`       → routes to the tasks tab focused on that task
@MainActor
private func processUITestingLaunchArgs(services: AppServices) {
    guard services.isUITestingMode else { return }
    let args = CommandLine.arguments

    if let i = args.firstIndex(of: "--simulated-deep-link"),
       i + 1 < args.count,
       let url = URL(string: args[i + 1]) {
        // Same dispatch the .onOpenURL closure uses.
        if url.scheme == "todus", let host = url.host {
            switch host {
            case "auth-callback", "link-callback":
                services.authService.handleAuthCallback(url: url)
            default:
                break
            }
        }
    }

    if let i = args.firstIndex(of: "--simulated-notification"),
       i + 1 < args.count {
        let payload = args[i + 1]
        if payload.hasPrefix("thread:") {
            let threadId = String(payload.dropFirst("thread:".count))
            services.pendingEmailThreadId = threadId
            services.navigateTo = .email
        } else if payload.hasPrefix("task:"),
                  let taskId = UUID(uuidString: String(payload.dropFirst("task:".count))) {
            services.pendingTaskId = taskId
            services.navigateTo = .tasks
        }
    }

    // Stub a pending AI mutation confirmation directly on the chat service.
    // C3 verifies the confirmation dialog actually surfaces when the service
    // sets `pendingMutationConfirmation`. We open the chat sheet at the same
    // time so the dialog has a presenter in the view hierarchy.
    if args.contains("--simulated-ai-mutation-pending") {
        // Stage the whole stub: flipping `showsAIChat` while MainTabView is
        // still mounting gets the sheet presentation silently dropped (and
        // `onDismiss` then resets the flag), and arming the confirmation
        // while the sheet is mid-transition makes `confirmationDialog`
        // silently skip presenting. Wait for the shell to settle, present
        // the sheet, then arm the dialog.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            services.showsAIChat = true
            try? await Task.sleep(for: .milliseconds(900))
            services.aiChatService.pendingMutationConfirmation = AIChatService.PendingMutationConfirmation(
                kind: .sendEmail,
                title: "Send email",
                subtitle: "To: test@example.com",
                body: "UI test stub"
            )
        }
    }

    // Post the calendar-authorization-changed notification so the calendar
    // tab + the permission view both refresh their `canReadEvents` cache.
    // C5 uses this to assert the calendar surface updates from a permission
    // change without needing to invoke the real EventKit prompt.
    if args.contains("--simulated-calendar-auth-changed") {
        NotificationCenter.default.post(
            name: .todusCalendarAuthorizationDidChange,
            object: nil
        )
    }
}

/// Result of the off-main ModelContainer initialization chain. ModelContainer is
/// Sendable, so it can cross the actor boundary back to MainActor.
private enum ContainerInitResult: Sendable {
    case success(ModelContainer)
    case failed
}

/// Text fields copied from `UNNotificationContent` before crossing to the main actor.
/// `UNNotificationContent` and `[AnyHashable: Any]` userInfo are not `Sendable`; `taskID` is
/// re-applied on the main actor from `taskIDString` to match `NotificationService.schedule`.
private struct SnoozeContentSnapshot: Sendable {
    let title: String
    let subtitle: String
    let body: String
    let categoryIdentifier: String
    let threadIdentifier: String
    let badge: Int?
}

// MARK: - AppDelegate (Notification Action Handling)

@MainActor
class AppDelegate: NSObject, UIApplicationDelegate {
    var modelContainer: ModelContainer?
    /// Optional handle so notification action failures can be surfaced in-app on the
    /// next launch (e.g. "Couldn't update task from notification — please retry").
    weak var services: AppServices?
    var pendingURL: URL?
    private var initializationFinished = false
    private var initializationWaiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilInitializationFinishes() async {
        guard !initializationFinished else { return }
        await withCheckedContinuation { continuation in
            initializationWaiters.append(continuation)
        }
    }

    func didFinishInitialization() {
        guard !initializationFinished else { return }
        initializationFinished = true
        let waiters = initializationWaiters
        initializationWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        // Tame root scroll views so vertical screens don’t feel like a two-axis “canvas”
        // (diagonal drifts + horizontal rubber-banding). Nested horizontal carousels
        // (folder chips, nudge cards, etc.) still scroll on their own axis; they just
        // won’t get horizontal edge bounce, which matches a mail/tasks app better.
        let scroll = UIScrollView.appearance()
        scroll.isDirectionalLockEnabled = true
        scroll.alwaysBounceHorizontal = false

        // The native iOS "More" tab list (shown because the TabView has >5 tabs;
        // here it holds Docs/Meetings) is a UIKit UITableView that paints pure
        // black in dark mode — inconsistent with the app's #1c1c1e. The app uses
        // no other UITableView (SwiftUI `List` is UICollectionView-backed on
        // iOS 16+), so this global appearance only affects that More list.
        let moreListBackground = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.109, alpha: 1.0)   // #1c1c1e, matches AppTheme.backgroundTop
                : UIColor.systemBackground
        }
        UITableView.appearance().backgroundColor = moreListBackground
        UITableViewCell.appearance().backgroundColor = .clear

        return true
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Mark delegate requirements as nonisolated to satisfy the protocol from a @MainActor type.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Extract only the values we need before hopping actors to avoid sending non-Sendable references.
        let userInfo = response.notification.request.content.userInfo
        let taskIDString = userInfo["taskID"] as? String ?? ""
        // Tap-routing payload keys — see NotificationService.swift:140 (threadId),
        // :191 (reminder threadId), :259 (conversationId), :102 (taskID).
        let threadIdString = userInfo["threadId"] as? String
        let conversationIdString = userInfo["conversationId"] as? String
        let categoryIdentifier = response.notification.request.content.categoryIdentifier
        let actionIdentifier = response.actionIdentifier
        let requestIdentifier = response.notification.request.identifier

        // Snooze: copy Sendable fields from UNNotificationContent here (nonisolated). Do not capture
        // UNNotificationContent in the MainActor Task — it is not Sendable and risks data races.
        let snoozeSnapshot: SnoozeContentSnapshot? = {
            guard actionIdentifier == NotificationService.Action.snooze else { return nil }
            let c = response.notification.request.content
            return SnoozeContentSnapshot(
                title: c.title,
                subtitle: c.subtitle,
                body: c.body,
                categoryIdentifier: c.categoryIdentifier,
                threadIdentifier: c.threadIdentifier,
                badge: c.badge?.intValue
            )
        }()

        // Call the completion handler immediately on the current (nonisolated) context
        // to avoid sending it across actors and risking data races.
        completionHandler()

        // Perform any UI/SwiftData work back on the main actor using only the captured primitives.
        Task { @MainActor in
            await self.waitUntilInitializationFinishes()
            guard let container = self.modelContainer else { return }

            // Handle actions based on the previously captured identifiers.
            switch actionIdentifier {
            case NotificationService.Action.complete:
                if let taskID = UUID(uuidString: taskIDString) {
                    let context = container.mainContext
                    let descriptor = FetchDescriptor<TaskRecord>(
                        predicate: #Predicate { task in task.id == taskID }
                    )
                    if let task = (try? context.fetch(descriptor))?.first {
                        if let captureService = self.services?.captureService {
                            // Route through the capture service so the completion gets a
                            // syncState, a server enqueue, and the Reminders mirror — the
                            // previous direct completed/status write here bypassed all
                            // three, so the task stayed open on web/macOS/Reminders and
                            // could be resurrected by the next server pull. (TD-06)
                            captureService.setStatus(task, status: .done, in: context)
                        } else {
                            // Services not wired yet (container is assigned just before
                            // services in deferred init) — fall back to the local-only
                            // write so the action still completes the task on-device.
                            task.completed = true
                            task.status = .done
                            task.updatedAt = .now
                            do {
                                try context.save()
                            } catch {
                                AppLogger.shared.log(
                                    "[TodosApp] Failed to save task completion from notification: \(error.localizedDescription)"
                                )
                                // Surface to next app open so the user knows the toggle didn't stick.
                                self.services?.pendingNotificationActionError =
                                    "Couldn't mark task complete from notification — please retry."
                            }
                        }
                    }
                }

            case NotificationService.Action.snooze:
                guard let s = snoozeSnapshot else { break }
                // Reschedule 1 hour from now; rebuild content on MainActor from sendable field copies.
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

                // Reacquire the notification center on this actor to avoid sending `center` across actors.
                let currentCenter = UNUserNotificationCenter.current()
                do {
                    try await currentCenter.add(request)
                } catch {
                    AppLogger.shared.log(
                        "[TodosApp] Failed to reschedule snoozed notification: \(error.localizedDescription)"
                    )
                    self.services?.pendingNotificationActionError =
                        "Couldn't snooze notification — please retry."
                }

            case NotificationService.Action.archiveEmail:
                // "Archive" action on a new-email notification: archive the thread in place
                // instead of routing the user into the app.
                guard let services = self.services,
                      let threadId = threadIdString, !threadId.isEmpty else { break }
                let archived = await services.emailService.archiveThreads(ids: [threadId])
                if archived {
                    // Clear the delivered notification for this thread. The scheduled identifier
                    // carries a timestamp suffix, so remove by the captured request identifier.
                    UNUserNotificationCenter.current()
                        .removeDeliveredNotifications(withIdentifiers: [requestIdentifier])
                } else {
                    services.pendingNotificationActionError =
                        "Couldn't archive email from notification — please retry."
                }

            default:
                // Default action (notification tap) and any other identifier: route based on payload.
                // Covers email thread, AI conversation, email reminder, and due-task digest taps.
                // Action-specific identifiers (TASK_COMPLETE / TASK_SNOOZE / EMAIL_ARCHIVE) are handled
                // above; everything else (including `UNNotificationDefaultActionIdentifier`) falls
                // through here so the user is taken to the relevant surface.
                guard let services = self.services else { return }

                if let threadId = threadIdString, !threadId.isEmpty {
                    // Email thread or email reminder: open the email tab and let
                    // EmailInboxView pop the thread via its pendingEmailThreadId observer.
                    services.pendingEmailThreadId = threadId
                    services.navigateTo = .email
                } else if let conversationId = conversationIdString, !conversationId.isEmpty {
                    // AI response: keep the destination in observable app state so it
                    // survives sheet presentation and cold-start timing.
                    services.pendingAIConversationId = conversationId
                    services.showsAIChat = true
                } else if !taskIDString.isEmpty,
                          let taskID = UUID(uuidString: taskIDString) {
                    // Due-task reminder tap: route to the tasks tab focused on the task.
                    services.pendingTaskId = taskID
                    services.navigateTo = .tasks
                } else if categoryIdentifier == "DUE_TASKS" {
                    // Digest tap without a specific task: take the user to the tasks tab.
                    services.navigateTo = .tasks
                }
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Present banner and sound even when app is in foreground
        completionHandler([.banner, .sound])
    }
}

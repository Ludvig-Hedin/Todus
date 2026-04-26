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
    /// Slug from a todus://share?slug=... deep link — presents SharedConversationView when set
    @State private var sharedConversationSlug: String? = nil
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if modelContainerFailed {
                modelContainerErrorView
            } else if let services, let modelContainer {
                RootView()
                    .environment(services)
                    .modelContainer(modelContainer)
                    .onOpenURL { url in
                        // mailto: links — open compose with pre-filled fields
                        if url.scheme == "mailto" {
                            handleMailtoURL(url, services: services)
                            return
                        }
                        services.authService.handleAuthCallback(url: url)
                        services.authStore.handleIncomingAuthCallback(url: url)
                        // todus://share?slug=abc123 — open shared conversation viewer
                        if url.host == "share",
                           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                           let slug = components.queryItems?.first(where: { $0.name == "slug" })?.value {
                            sharedConversationSlug = slug
                        }
                    }
                    .sheet(item: Binding(
                        get: { sharedConversationSlug.map { SlugWrapper(slug: $0) } },
                        set: { sharedConversationSlug = $0?.slug }
                    )) { wrapper in
                        SharedConversationView(slug: wrapper.slug)
                            .environment(services)
                            .presentationDragIndicator(.visible)
                            .appSheetBackground()
                    }
                    .tint(AppTheme.accent)
                    .preferredColorScheme(services.appearancePreference.colorScheme)
                    .onChange(of: scenePhase) { oldPhase, newPhase in
                        if newPhase == .background {
                            AvatarCache.shared.flushPendingSaves()
                            WidgetUpdateManager.shared.updateWidgets(
                                context: modelContainer.mainContext,
                                emailService: services.emailService
                            )
                        }
                    }
            } else {
                // Lightweight splash — renders instantly while services initialize
                splashView
                    .task { await initializeApp() }
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

        let schema = Schema([TaskRecord.self, FolderRecord.self, FolderItemRecord.self])

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
            return
        }

        // Yield to let the run loop process any pending UI work (keeps splash responsive)
        await Task.yield()

        // Assign container to appDelegate BEFORE setting @State so notification
        // actions can resolve tasks immediately — avoids race with onAppear.
        appDelegate.modelContainer = container

        let svc = AppServices()
        // Wire AppServices into AppDelegate so notification-action failures (which run
        // outside SwiftUI environment) can surface a user-facing error state.
        appDelegate.services = svc

        svc.modelContainer = container
        svc.setupNetworkSync()

        self.modelContainer = container
        self.services = svc
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

/// Identifiable wrapper for a share slug — used to drive the SharedConversationView sheet
/// from a `todus://share?slug=...` deep link.
private struct SlugWrapper: Identifiable {
    let slug: String
    var id: String { slug }
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

            default:
                break
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

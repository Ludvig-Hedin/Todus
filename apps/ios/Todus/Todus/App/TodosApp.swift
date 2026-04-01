import SwiftUI
import SwiftData
import UserNotifications

@main
struct TodosApp: App {
    // Deferred initialization — services and model container are created AFTER the first
    // frame renders, so the user sees a branded splash instead of a 9+ second black screen.
    // Previously both were initialized synchronously in init(), blocking the main thread.
    @State private var services: AppServices?
    @State private var modelContainer: ModelContainer?
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Slug from a todus://share?slug=... deep link — presents SharedConversationView when set
    @State private var sharedConversationSlug: String? = nil

    var body: some Scene {
        WindowGroup {
            if let services, let modelContainer {
                RootView()
                    .environment(services)
                    .modelContainer(modelContainer)
                    .onOpenURL { url in
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
                    }
                    .tint(AppTheme.accent)
                    .preferredColorScheme(services.appearancePreference.colorScheme)
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

        let schema = Schema([TaskRecord.self, FolderRecord.self])

        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema)
        } catch {
            let fallbackURL = FileManager.default.temporaryDirectory.appendingPathComponent("TodosFallback.store")
            let fallbackConfiguration = ModelConfiguration(url: fallbackURL, allowsSave: true)
            do {
                container = try ModelContainer(for: schema, configurations: fallbackConfiguration)
            } catch {
                let inMemoryConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                do {
                    container = try ModelContainer(for: schema, configurations: inMemoryConfig)
                } catch {
                    fatalError("Failed to create model container even in memory: \(error)")
                }
            }
        }

        // Yield to let the run loop process any pending UI work (keeps splash responsive)
        await Task.yield()

        // Assign container to appDelegate BEFORE setting @State so notification
        // actions can resolve tasks immediately — avoids race with onAppear.
        appDelegate.modelContainer = container

        let svc = AppServices()

        self.modelContainer = container
        self.services = svc
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

/// Identifiable wrapper for a share slug — used to drive the SharedConversationView sheet
/// from a `todus://share?slug=...` deep link.
private struct SlugWrapper: Identifiable {
    let slug: String
    var id: String { slug }
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

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
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
                            print("[TodosApp] Failed to save task completion from notification: \(error)")
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
                    print("[TodosApp] Failed to reschedule snoozed notification: \(error)")
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

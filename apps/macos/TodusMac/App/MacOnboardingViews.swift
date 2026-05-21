import SwiftUI
import SwiftData
import AppKit

private struct MacOnboardingShell<Content: View>: View {
    let step: Int
    let title: String
    let subtitle: String
    let icon: AnyView
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            MacTheme.contentBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 12) {
                    icon
                        .frame(width: 88, height: 88)

                    Text(title)
                        .font(.system(size: 24, weight: .semibold))
                        .tracking(-0.3)
                        .multilineTextAlignment(.center)

                    Text(subtitle)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(MacTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                Spacer().frame(height: 28)

                content()
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 24)

                Spacer()
            }
            .padding(.vertical, 32)
        }
        .animation(MacTheme.Motion.base, value: step)
    }
}

/// Primary capsule button (white on accent) — shared with inbox “Connect Gmail” and onboarding.
struct MacOnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.88 : 1))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .interactiveHitTarget(expansion: 6)
            .pointerStyle(.link)
            .background(MacTheme.accent.opacity(configuration.isPressed ? 0.88 : 1), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

private struct MacOnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(MacTheme.textSecondary.opacity(configuration.isPressed ? 0.85 : 1))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .interactiveHitTarget(expansion: 6)
            .pointerStyle(.link)
            .background(MacTheme.surfaceCard.opacity(configuration.isPressed ? 0.96 : 1), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(MacTheme.cardBorder, lineWidth: 1)
            )
    }
}

struct MacGmailOnboardingView: View {
    @Environment(MacAppServices.self) private var services
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        MacOnboardingShell(
            step: 1,
            title: "Connect Gmail",
            subtitle: "Connect Gmail to read and draft email here. If you skip, you can keep using tasks and connect Gmail later in Settings.",
            icon: AnyView(GmailIconView(size: 88))
        ) {
            VStack(spacing: 12) {
                onboardingMessage(
                    text: errorMessage ?? "This takes about a minute. You can always change it later in Settings.",
                    tint: errorMessage == nil ? MacTheme.textSecondary : .red
                )

                Button {
                    Task { await connect() }
                } label: {
                    HStack(spacing: 8) {
                        GmailIconView(size: 20)
                        if isConnecting {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.85)
                        }
                        Text(isConnecting ? "Connecting…" : (errorMessage != nil ? "Try again" : "Connect Gmail"))
                    }
                }
                .buttonStyle(MacOnboardingPrimaryButtonStyle())
                .disabled(isConnecting)

                Button("Skip, use tasks only for now") {
                    services.hasConfiguredGmailPrompt = true
                }
                .buttonStyle(MacOnboardingSecondaryButtonStyle())
            }
        }
    }

    private func connect() async {
        isConnecting = true
        errorMessage = nil
        await services.authService.signInWithGoogle()
        if services.authService.isAuthenticated {
            await services.emailService.checkConnection()
            if services.emailService.hasConnection {
                await services.emailService.loadThreads(refresh: true)
            }
            services.hasConfiguredGmailPrompt = true
        } else {
            errorMessage = services.authService.lastErrorMessage
                ?? "Connection did not finish. You can try again or set this up later in Settings."
        }
        isConnecting = false
    }
}

struct MacRemindersOnboardingView: View {
    @Environment(MacAppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @State private var isConnecting = false
    @State private var deniedMessage: String?

    var body: some View {
        MacOnboardingShell(
            step: 3,
            title: "Connect Apple Reminders",
            subtitle: "Connect Apple Reminders to keep your tasks aligned. If you skip, Todus still works normally and you can turn sync on later in Settings.",
            icon: AnyView(AppleRemindersIconView(size: 88))
        ) {
            VStack(spacing: 12) {
                if let deniedMessage {
                    onboardingMessage(text: deniedMessage, tint: Color.red)
                } else {
                    onboardingMessage(
                        text: "We only ask once here. You can revisit this anytime in Settings.",
                        tint: MacTheme.textSecondary
                    )
                }

                Button {
                    Task { await connect() }
                } label: {
                    HStack(spacing: 8) {
                        AppleRemindersIconView(size: 20)
                        if isConnecting {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.85)
                        }
                        Text(isConnecting ? "Connecting…" : "Connect Apple Reminders")
                    }
                }
                .buttonStyle(MacOnboardingPrimaryButtonStyle())
                .disabled(isConnecting)

                Button("Skip, set this up later in Settings") {
                    services.hasConfiguredRemindersPrompt = true
                }
                .buttonStyle(MacOnboardingSecondaryButtonStyle())
            }
        }
    }

    private func connect() async {
        isConnecting = true
        deniedMessage = nil
        let granted: Bool
        switch services.remindersSyncService.authorizationState() {
        case .authorized, .writeOnly:
            // `.writeOnly` is sufficient for one-way (toReminders) sync — the
            // underlying workers accept it. Treating it as denied here caused
            // a false "Permission was not granted" path even though sync works.
            granted = true
        case .notDetermined:
            granted = await services.remindersSyncService.requestAccess()
        case .restricted, .denied:
            granted = false
        }
        if granted {
            services.remindersSyncEnabled = true
            await services.importFromReminders(in: modelContext)
            services.syncExistingTasksToReminders(in: modelContext)
            services.hasConfiguredRemindersPrompt = true
        } else {
            services.remindersSyncEnabled = false
            deniedMessage = "Permission was not granted. You can keep going and enable Reminders later in Settings."
        }
        isConnecting = false
    }
}

struct MacCalendarOnboardingView: View {
    @Environment(MacAppServices.self) private var services
    @State private var isRequestingAccess = false
    @State private var permissionMessage: String?

    var body: some View {
        MacOnboardingShell(
            step: 2,
            title: "Enable Calendar Access",
            subtitle: "Enable calendar access to bring today’s schedule into Todus. If you skip, you can keep using tasks and email and turn this on later in Settings.",
            icon: AnyView(AppleCalendarIconView(size: 88))
        ) {
            VStack(spacing: 12) {
                onboardingMessage(
                    text: permissionMessage ?? "We only use this to show your schedule inside Todus.",
                    tint: permissionMessage == nil ? MacTheme.textSecondary : .red
                )

                if permissionMessage != nil {
                    // Permission was denied — surface a primary Continue so users
                    // aren't trapped. The "Skip" button is hidden in this state
                    // because it would do the exact same thing as Continue, and
                    // two identically-behaved buttons read as a UI bug.
                    Button {
                        services.hasConfiguredCalendarPrompt = true
                    } label: {
                        Text("Continue")
                    }
                    .buttonStyle(MacOnboardingPrimaryButtonStyle())
                } else {
                    Button {
                        Task { await requestAccess() }
                    } label: {
                        HStack(spacing: 8) {
                            AppleCalendarIconView(size: 20)
                            if isRequestingAccess {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.85)
                            }
                            Text(isRequestingAccess ? "Requesting…" : "Enable Calendar Access")
                        }
                    }
                    .buttonStyle(MacOnboardingPrimaryButtonStyle())
                    .disabled(isRequestingAccess)

                    Button("Skip, set this up later in Settings") {
                        services.hasConfiguredCalendarPrompt = true
                    }
                    .buttonStyle(MacOnboardingSecondaryButtonStyle())
                }
            }
        }
    }

    private func requestAccess() async {
        isRequestingAccess = true
        let granted = await services.calendarService.requestAccess()
        if granted {
            services.hasConfiguredCalendarPrompt = true
        } else {
            permissionMessage = "Calendar access was not granted. You can keep going and enable it later in Settings."
        }
        isRequestingAccess = false
    }
}

struct MacStartupOnboardingView: View {
    @Environment(MacAppServices.self) private var services
    @AppStorage("mac_startup_view") private var startupView = "home"
    @State private var selectedStartupView = "home"

    private struct StartupOption: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
    }

    private let options: [StartupOption] = [
        .init(id: "home", title: "Home", subtitle: "Recommended: start with your daily overview", icon: "house"),
        .init(id: "inbox", title: "Inbox", subtitle: "Read email first", icon: "tray"),
        .init(id: "tasks", title: "Tasks", subtitle: "Capture work first", icon: "checkmark.square"),
        .init(id: "meetings", title: "Meetings", subtitle: "Review calls first", icon: "video"),
    ]

    var body: some View {
        MacOnboardingShell(
            step: 4,
            title: "Choose your launch page",
            subtitle: "Pick what opens first when Todus starts. This is just a preference and you can change it later in Settings.",
            icon: AnyView(Image(systemName: "sidebar.left")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(MacTheme.accent))
        ) {
            VStack(spacing: 12) {
                onboardingMessage(
                    text: "Home is the safest default if you are not sure yet.",
                    tint: MacTheme.textSecondary
                )

                VStack(spacing: 8) {
                    ForEach(options) { option in
                        Button {
                            withAnimation(MacTheme.Motion.base) {
                                selectedStartupView = option.id
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: option.icon)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(MacTheme.accent)
                                    .frame(width: 32, height: 32)
                                    .background(MacTheme.surfaceHover, in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(MacTheme.textPrimary)
                                    Text(option.subtitle)
                                        .font(.system(size: 12))
                                        .foregroundStyle(MacTheme.textSecondary)
                                }

                                Spacer()

                                if selectedStartupView == option.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(MacTheme.accent)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                selectedStartupView == option.id ? MacTheme.surfaceHover : MacTheme.surfaceCard,
                                in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                                    .stroke(
                                        selectedStartupView == option.id ? MacTheme.accent.opacity(0.22) : MacTheme.cardBorder,
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(spacing: 12) {
                    Button {
                        startupView = selectedStartupView
                        services.startupView = selectedStartupView
                        services.hasConfiguredStartupViewPrompt = true
                    } label: {
                        Text("Use this view")
                    }
                    .buttonStyle(MacOnboardingPrimaryButtonStyle())

                    Button("Skip, keep the recommended start page") {
                        startupView = "home"
                        services.startupView = "home"
                        services.hasConfiguredStartupViewPrompt = true
                    }
                    .buttonStyle(MacOnboardingSecondaryButtonStyle())
                }
                .padding(.top, 4)
            }
            .onAppear {
                selectedStartupView = services.startupView.isEmpty ? "home" : services.startupView
            }
        }
    }
}

struct MacNotificationsOnboardingView: View {
    @Environment(MacAppServices.self) private var services
    @State private var isRequesting = false
    @State private var requestResult: Bool? = nil

    var body: some View {
        MacOnboardingShell(
            step: 5,
            title: "Stay on top of it all",
            subtitle: "Get notified about new emails, tasks due today, AI replies, and reminders — without having to keep the app open.",
            icon: AnyView(
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(MacTheme.accent)
            )
        ) {
            VStack(spacing: 12) {
                notificationFeatureRows

                Spacer().frame(height: 4)

                if let result = requestResult {
                    onboardingMessage(
                        text: result
                            ? "Notifications are on. Adjust them anytime in Settings."
                            : "Notifications are off. Enable them later in System Settings → Notifications.",
                        tint: result ? .green : MacTheme.textSecondary
                    )

                    Button {
                        services.hasConfiguredNotificationsPrompt = true
                    } label: {
                        Text("Continue")
                    }
                    .buttonStyle(MacOnboardingPrimaryButtonStyle())
                } else {
                    onboardingMessage(
                        text: "We only ask once. You can turn each type on or off later in Settings.",
                        tint: MacTheme.textSecondary
                    )

                    Button {
                        Task { await requestPermission() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "bell.fill")
                            if isRequesting {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.85)
                            }
                            Text(isRequesting ? "Requesting…" : "Enable Notifications")
                        }
                    }
                    .buttonStyle(MacOnboardingPrimaryButtonStyle())
                    .disabled(isRequesting)

                    Button("Skip, decide later") {
                        services.hasConfiguredNotificationsPrompt = true
                    }
                    .buttonStyle(MacOnboardingSecondaryButtonStyle())
                }
            }
        }
    }

    private var notificationFeatureRows: some View {
        VStack(spacing: 0) {
            macNotificationRow(icon: "envelope.fill", title: "New emails", subtitle: "Incoming messages from connected accounts")
            Divider().padding(.leading, 48)
            macNotificationRow(icon: "checkmark.square.fill", title: "Task reminders", subtitle: "1 hour before a task is due and a daily digest")
            Divider().padding(.leading, 48)
            macNotificationRow(icon: "sparkles", title: "AI responses", subtitle: "When Todus AI replies while you're away")
            Divider().padding(.leading, 48)
            macNotificationRow(icon: "calendar", title: "Calendar events", subtitle: "Reminders for upcoming meetings and events")
        }
        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 1)
        )
    }

    private func macNotificationRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MacTheme.accent)
                .frame(width: 26, height: 26)
                .background(MacTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func requestPermission() async {
        isRequesting = true
        requestResult = await services.notificationService.requestPermission()
        isRequesting = false
    }
}

struct MacDefaultMailOnboardingView: View {
    @Environment(MacAppServices.self) private var services

    var body: some View {
        MacOnboardingShell(
            step: 6,
            title: "Make Todus your mail app",
            subtitle: "Clicking any email link — in Safari, Finder, or anywhere on your Mac — will open it here instead of Apple Mail.",
            icon: AnyView(
                ZStack {
                    Circle()
                        .fill(MacTheme.accent.opacity(0.1))
                        .frame(width: 88, height: 88)
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(MacTheme.accent)
                }
            )
        ) {
            VStack(spacing: 12) {
                onboardingMessage(
                    text: "Open System Settings → General → Default Apps and choose Todus for Email.",
                    tint: MacTheme.textSecondary
                )

                Button {
                    openSystemSettings()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gear")
                        Text("Open System Settings")
                    }
                }
                .buttonStyle(MacOnboardingPrimaryButtonStyle())

                Button("Done, I've set it") {
                    services.hasConfiguredDefaultMailPrompt = true
                }
                .buttonStyle(MacOnboardingSecondaryButtonStyle())

                // Skip is intentionally de-emphasized vs. "Done, I've set it" to
                // avoid two visually identical actions competing for the user's eye.
                Button("Skip, keep my current app") {
                    services.hasConfiguredDefaultMailPrompt = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MacTheme.textSecondary)
                .padding(.top, 2)
            }
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.General-Settings") {
            NSWorkspace.shared.open(url)
        }
    }
}

private func onboardingMessage(text: String, tint: Color) -> some View {
    // Status-aware icon — color alone isn't enough of a signal for green/red states.
    // Falls through to no icon for the neutral secondary tint.
    let systemImage: String? = {
        if tint == .green { return "checkmark.circle.fill" }
        if tint == .red { return "exclamationmark.triangle.fill" }
        return nil
    }()
    return HStack(alignment: .top, spacing: 8) {
        if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
        }
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity)
    .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
            .stroke(tint.opacity(0.12), lineWidth: 1)
    )
}

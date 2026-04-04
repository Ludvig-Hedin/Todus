import SwiftUI
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
        .animation(.snappy(duration: 0.25), value: step)
    }
}

private struct MacOnboardingPrimaryButtonStyle: ButtonStyle {
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
                        Text(isConnecting ? "Connecting…" : "Connect Gmail")
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
            step: 3,
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
                            withAnimation(.snappy(duration: 0.2)) {
                                selectedStartupView = option.id
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: option.icon)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(MacTheme.accent)
                                    .frame(width: 32, height: 32)
                                    .background(MacTheme.surfaceHover, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

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

private func onboardingMessage(text: String, tint: Color) -> some View {
    Text(text)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(tint)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        )
}

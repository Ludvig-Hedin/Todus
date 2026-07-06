import SwiftUI
import SwiftData

struct GmailOnboardingView: View {
    @Environment(AppServices.self) private var services
    @State private var isConnecting = false
    @State private var errorMessage: String?
    /// True while the initial "is Gmail already connected?" check runs, so we
    /// can show lightweight feedback instead of silently sitting there before
    /// either rendering this screen or auto-advancing past it.
    @State private var isCheckingExistingConnection = true

    var body: some View {
        ZStack {
            AppTheme.backgroundTop.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                GmailIconView(size: 88)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Gmail icon")

                Spacer().frame(height: 24)

                Text("Connect Gmail")
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                Spacer().frame(height: 12)

                Text("Connect Gmail to read and draft email here. If you skip, Todus still works for tasks and you can connect Gmail later in Settings.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AppTheme.mutedText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer().frame(height: 28)

                VStack(spacing: 12) {
                    if let errorMessage {
                        onboardingMessage(
                            text: errorMessage,
                            tint: AppTheme.danger
                        )
                    } else {
                        onboardingMessage(
                            text: "This takes about a minute. You can always change it later in Settings.",
                            tint: AppTheme.mutedText
                        )
                    }

                    Button {
                        isConnecting = true
                        errorMessage = nil
                        Task {
                            let didConnect = await services.emailService.connectGmail(
                                authService: services.authService
                            )
                            if didConnect {
                                // Refresh the cached connections list so the new
                                // mailbox shows up in Settings → Accounts and the
                                // From picker without waiting for the next launch.
                                await services.connectionsService.loadConnections()
                                services.hasConfiguredGmailPrompt = true
                            } else {
                                errorMessage = services.emailService.errorMessage
                                    ?? services.authService.lastErrorMessage
                                    ?? "Connection did not finish. You can try again or set this up later in Settings."
                            }
                            isConnecting = false
                        }
                    } label: {
                        HStack(spacing: 10) {
                            GmailIconView(size: 20)
                            if isConnecting {
                                ButtonInlineProgressView()
                            }
                            Text(isConnecting ? "Connecting…" : "Connect Gmail")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .disabled(isConnecting)
                    .sensoryFeedback(.selection, trigger: isConnecting)

                    Button {
                        services.hasConfiguredGmailPrompt = true
                    } label: {
                        Text("Skip, use tasks only for now")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppTheme.mutedText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    // Block tapping Skip mid-connection so we don't advance past Gmail
                    // before the OAuth callback completes (and end up with a half-set
                    // connection state).
                    .disabled(isConnecting)
                    .accessibilityHint("Skip connecting Gmail for now")
                }
                .padding(.horizontal, 24)
                // Fade the content in only once we know we're not about to
                // auto-advance — otherwise this screen would flash briefly
                // before being replaced by the next onboarding step.
                .opacity(isCheckingExistingConnection ? 0 : 1)
                .overlay {
                    if isCheckingExistingConnection {
                        ProgressView()
                    }
                }

                Spacer()
            }
            .padding(.vertical, 32)
        }
        .animation(AppTheme.Motion.fast, value: isCheckingExistingConnection)
        // Auto-advance if Gmail is already connected (e.g. sign-in with Google
        // auto-created a connection via the server accountCreateHook).
        .task {
            // Fast path: if we already know a mailbox is connected (restored
            // from cache in EmailService.init), skip this step IMMEDIATELY rather
            // than rendering the full "Connect Gmail" screen for the ~2s the
            // forced network check takes and then yanking it away — the flash
            // that read as a bug.
            if services.emailService.hasConnection {
                services.hasConfiguredGmailPrompt = true
                return
            }
            await services.emailService.checkConnection(force: true)
            isCheckingExistingConnection = false
            if services.emailService.hasConnection {
                services.hasConfiguredGmailPrompt = true
            }
        }
    }

    private func onboardingMessage(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                    .stroke(tint.opacity(0.12), lineWidth: 1)
            )
    }
}

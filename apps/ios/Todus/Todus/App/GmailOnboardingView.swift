import SwiftUI
import SwiftData

struct GmailOnboardingView: View {
    @Environment(AppServices.self) private var services
    @State private var isConnecting = false
    @State private var errorMessage: String?

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
                    .accessibilityHint("Skip connecting Gmail for now")
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .padding(.vertical, 32)
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

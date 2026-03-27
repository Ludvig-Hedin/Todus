import SwiftUI
import SwiftData

struct GmailOnboardingView: View {
    @Environment(AppServices.self) private var services
    @State private var isConnecting = false

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

                Text("Grant access to your Gmail so Todus can fetch your emails.\nYou can change this later in Settings.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AppTheme.mutedText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer().frame(height: 40)

                VStack(spacing: 12) {
                    Button {
                        isConnecting = true
                        Task {
                            await services.authService.signInWithGoogle()
                            if services.authService.isAuthenticated {
                                services.hasConfiguredGmailPrompt = true
                            }
                            isConnecting = false
                        }
                    } label: {
                        HStack(spacing: 10) {
                            GmailIconView(size: 20)
                            if isConnecting {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.85)
                            }
                            Text(isConnecting ? "Connecting…" : "Connect Gmail")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .disabled(isConnecting)
                    .accessibilityHint("Connect your Gmail account")

                    Button {
                        services.hasConfiguredGmailPrompt = true
                    } label: {
                        Text("Skip for now")
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
}


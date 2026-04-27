import SwiftUI

/// Shown when the user has no email connection.
///
/// Google sign-in gives authentication only — Gmail API access (read/send mail)
/// requires a *separate* OAuth consent for mail scopes. This screen grants those scopes
/// and stores the resulting connection in the backend.
///
/// Visual style matches GmailOnboardingView exactly for consistency.
struct EmailConnectView: View {
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

                Text("Grant access to your Gmail inbox\nto view and send emails.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AppTheme.mutedText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Show error if connection attempt failed
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                }

                Spacer().frame(height: 40)

                Button {
                    guard !isConnecting else { return }
                    isConnecting = true
                    errorMessage = nil
                    Task {
                        let didConnect = await services.emailService.connectGmail(
                            authService: services.authService
                        )
                        if !didConnect {
                            // EmailService.connectGmail now classifies errors (cancellation,
                            // URLError, generic) into specific user-facing strings, so we
                            // surface its message verbatim instead of overriding it here.
                            errorMessage = services.emailService.errorMessage
                                ?? services.authService.lastErrorMessage
                                ?? "Could not link your Gmail account. "
                                + "Make sure you granted access to Gmail and try again."
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
                .padding(.horizontal, 24)
                .accessibilityHint("Connect your Gmail account")

                Spacer()
            }
            .padding(.vertical, 32)
        }
    }
}

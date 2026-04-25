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
                        // Match the web app's `authClient.linkSocial({ provider: 'google' })`
                        // flow: always open a fresh Google OAuth consent session and link
                        // the resulting tokens to the current user. If the user isn't yet
                        // authenticated, fall back to a full sign-in (which also grants
                        // Gmail scopes through the provider config).
                        do {
                            if services.authService.isAuthenticated {
                                try await services.authService.linkSocialAccount(provider: "google")
                            } else {
                                await services.authService.signInWithGoogle()
                                if !services.authService.isAuthenticated {
                                    errorMessage = services.authService.lastErrorMessage
                                        ?? "Sign in failed. Please try again."
                                    isConnecting = false
                                    return
                                }
                            }
                        } catch {
                            errorMessage = services.authService.lastErrorMessage
                                ?? "Could not open Google sign-in. Please try again."
                            isConnecting = false
                            return
                        }

                        // Backend `account.create.after` / `account.update.after` hooks run
                        // asynchronously after the OAuth redirect. The connection row may
                        // not exist at the instant we get the deep-link callback, so retry
                        // a few times with short backoff before giving up.
                        var attempt = 0
                        let maxAttempts = 6
                        while attempt < maxAttempts {
                            await services.emailService.checkConnection(force: true)
                            if services.emailService.hasConnection { break }
                            attempt += 1
                            if attempt < maxAttempts {
                                try? await Task.sleep(nanoseconds: 500_000_000)
                            }
                        }

                        if services.emailService.hasConnection {
                            await services.emailService.loadThreads(refresh: true)
                        } else {
                            errorMessage = "Could not link your Gmail account. "
                                + "Make sure you granted access to Gmail and try again."
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
                .padding(.horizontal, 24)
                .accessibilityHint("Connect your Gmail account")

                Spacer()
            }
            .padding(.vertical, 32)
        }
    }
}

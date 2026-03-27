import SwiftUI

/// Shown when the user has no email connection.
///
/// Google sign-in gives authentication only — Gmail API access (read/send mail)
/// requires a *separate* OAuth consent for mail scopes. This screen grants those scopes
/// and stores the resulting connection in the backend.
struct EmailConnectView: View {
    @Environment(AppServices.self) private var services
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(AppTheme.subtleText)

            VStack(spacing: 8) {
                Text("Connect Gmail")
                    .font(.system(size: 22, weight: .bold))

                // Clarify that this is a separate step from Google sign-in
                Text("Grant access to your Gmail inbox\nto view and send emails.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.subtleText)
                    .multilineTextAlignment(.center)
            }

            // Show error if connection attempt failed
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // Single Gmail connect button — Outlook is not supported
            Button {
                guard !isLoading else { return }
                isLoading = true
                errorMessage = nil
                Task {
                    do {
                        await services.authService.signInWithGoogle()
                        await services.emailService.checkConnection()
                        if services.emailService.hasConnection {
                            await services.emailService.loadThreads(refresh: true)
                        }
                    } catch {
                        errorMessage = "Connection failed. Please try again."
                    }
                    isLoading = false
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Connect Gmail")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                // Use explicit blue so the button is always legible in both light and dark mode
                .background(Color.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .opacity(isLoading ? 0.6 : 1.0)
            .padding(.horizontal, 24)

            Spacer()
            Spacer()
        }
    }
}

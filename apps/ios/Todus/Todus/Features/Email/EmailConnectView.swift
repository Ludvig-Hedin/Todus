import SwiftUI

/// Shown when the user has no email connection — prompts to connect Gmail or Outlook.
/// For Google sign-in users, Gmail may already be connected via OAuth scopes.
struct EmailConnectView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(AppTheme.subtleText)

            VStack(spacing: 8) {
                Text("Connect Your Email")
                    .font(.system(size: 22, weight: .bold))

                Text("Link your Gmail or Outlook account\nto view and send emails.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.subtleText)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                // Connect Gmail — opens the Google OAuth flow
                Button {
                    Task { await services.authService.signInWithGoogle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Connect Gmail")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(AppTheme.backgroundTop)
                }
                .buttonStyle(.plain)

                // Connect Outlook — placeholder for future implementation
                Button {
                    // Outlook OAuth flow — not yet implemented
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Connect Outlook")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)

            Spacer()
            Spacer()
        }
    }
}

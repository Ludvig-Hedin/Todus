import SwiftUI

/// Branded entry card — first thing a new install sees before the sign-in flow.
///
/// Mirrors the macOS startup card visually (app icon hero, brand title, short
/// tagline, primary "Get started" / secondary "I already have an account").
/// Both CTAs flip `services.hasSeenStartupCard = true` and surface the existing
/// `AuthView` via `RootView`'s normal routing. No new auth flow is introduced —
/// this card is a single one-shot brand entry that retires itself on first use.
struct StartupOnboardingView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.colorScheme) private var colorScheme

    /// Accent used for the primary CTA. Matches the brand accent used elsewhere
    /// (e.g. AuthView's "Send code" button) so the entry card feels consistent
    /// with what the user sees one tap later. Sourced from `AppTheme.Accents.blue`
    /// so a future rebrand changes both surfaces in one place.
    private let accentBlue = AppTheme.Accents.blue

    var body: some View {
        ZStack {
            AppTheme.backgroundTop
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                hero
                    .padding(.horizontal, 32)

                Spacer(minLength: 24)

                ctaStack
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                legalLinks
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 16) {
            // App icon hero — uses the existing BrandLogo asset (template-rendered
            // so it tracks light/dark mode), wrapped in a soft squircle backdrop
            // that mirrors the macOS startup card's iconography treatment.
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(AppTheme.surfacePrimary)
                    .frame(width: 104, height: 104)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    )
                    .shadow(color: AppTheme.shadowColor, radius: 12, x: 0, y: 6)

                Image("BrandLogo")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(.primary)
                    .frame(width: 56, height: 56)
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Todus")
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(.primary)

                Text("Email, tasks, and calendar — one calm workspace.")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.primary.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Call to action

    private var ctaStack: some View {
        VStack(spacing: 12) {
            Button {
                services.hasSeenStartupCard = true
            } label: {
                Text("Get started")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(accentBlue, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("startup.getStartedButton")
            // Both CTAs open the same sign-in screen (which handles new + returning
            // users), so the hints describe that honestly rather than promising two
            // different destinations the buttons don't actually have.
            .accessibilityHint("Continues to the sign-in screen, where you can create an account or sign in")

            Button {
                services.hasSeenStartupCard = true
            } label: {
                Text("I already have an account")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color(UIColor.systemBackground), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color(UIColor.separator), lineWidth: 1)
                    )
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Continues to the same sign-in screen, where you can sign in or create an account")
        }
        .frame(maxWidth: 420)
    }

    // MARK: - Legal links

    /// Mirrors the AuthView legal row so the brand card and the sign-in screen
    /// share the same bottom-of-screen treatment.
    private var legalLinks: some View {
        HStack(spacing: 8) {
            Button {
                if let url = URL(string: "https://todus.app/terms") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Terms of Service")
            }
            Circle().fill(.secondary.opacity(0.5)).frame(width: 3, height: 3)
            Button {
                if let url = URL(string: "https://todus.app/privacy") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Privacy Policy")
            }
        }
        .font(.system(size: 13, weight: .regular))
        .foregroundStyle(.secondary.opacity(0.7))
        .buttonStyle(.plain)
    }
}

import SwiftUI

/// Optional product tour shown right before the final tab-bar setup step.
///
/// Two-phase UX:
///   • Phase 1 (consent) — single screen with a prominent **Skip** and a smaller
///     "Show me around" CTA. Most users tap Skip and never see the tour again.
///   • Phase 2 (explainer) — three compact paginated cards explaining the
///     headline features. A persistent "Skip" link sits in the top-right so the
///     user can bail at any point without missing the actual onboarding.
///
/// On dismissal (either path) we flip `services.hasSeenWelcomeTour` so the
/// onboarding chain in `RootView` advances to the next step exactly once.
struct WelcomeTourView: View {
    @Environment(AppServices.self) private var services

    /// Two-phase tour state. `.consent` is the first screen with Skip/Show; once
    /// the user opts in we move to `.pages` and start paginating the explainers.
    private enum Phase {
        case consent
        case pages
    }

    @State private var phase: Phase = .consent
    @State private var pageIndex: Int = 0

    /// Static content for the three explainer cards. Kept short — every card
    /// has to be readable in one glance or it loses to the Skip button.
    private struct TourPage: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let body: String
    }

    private let pages: [TourPage] = [
        TourPage(
            id: 0,
            symbol: "tray.full",
            title: "Email, tasks, and calendar in one place",
            body: "Triage your inbox, capture tasks, and check today's events without app-switching."
        ),
        TourPage(
            id: 1,
            symbol: "sparkles",
            title: "AI that reads your day, not your data",
            body: "Tap the sparkle button anytime for a briefing, a draft reply, or a quick triage of what matters now."
        ),
        TourPage(
            id: 2,
            symbol: "rectangle.grid.2x2",
            title: "Make it yours",
            body: "Next step lets you pick the pages that show up in the tab bar — iOS only has room for 5, so choose wisely."
        ),
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AppTheme.backgroundTop.ignoresSafeArea()

            switch phase {
            case .consent:
                consent
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            case .pages:
                explainer
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            // Always-visible Skip in the corner — the explicit escape hatch the
            // user instructions demand. Hidden on the consent screen because the
            // big "Skip" button there already serves the same role.
            if phase == .pages {
                // Hit target is the full 44×44 capsule, not just the visible
                // chrome — `contentShape` extends tap area beyond the rendered
                // pill so a user tapping just outside it still triggers Skip.
                Button { finish() } label: {
                    Text("Skip")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(AppTheme.cardBorder.opacity(0.6), lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                .padding(.trailing, 16)
                .transition(.opacity)
                .accessibilityLabel("Skip the product tour")
            }
        }
        .animation(AppTheme.Motion.base, value: phase)
    }

    // MARK: - Consent

    private var consent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)

            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(AppTheme.surfacePrimary)
                        .frame(width: 96, height: 96)
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .stroke(AppTheme.cardBorder, lineWidth: 1)
                        )
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(.primary)
                }
                .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text("Want a 30-second tour?")
                        .font(.system(size: 24, weight: .bold))
                        .tracking(-0.3)
                        .multilineTextAlignment(.center)

                    Text("Three quick cards on what Todus does and how to move fast. You can always skip — most people do.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 24)

            VStack(spacing: 10) {
                Button {
                    finish()
                } label: {
                    Text("Skip")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(AppPrimaryButtonStyle())
                .accessibilityIdentifier("welcomeTour.skip.primary")

                Button {
                    withAnimation(AppTheme.Motion.base) {
                        phase = .pages
                        pageIndex = 0
                    }
                } label: {
                    Text("Show me around")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("welcomeTour.show")
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Explainer pages

    private var explainer: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 56)

            TabView(selection: $pageIndex) {
                ForEach(pages) { page in
                    pageCard(page)
                        .tag(page.id)
                        .padding(.horizontal, 24)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 320)

            pageDots
                .padding(.top, 4)

            Spacer()

            VStack(spacing: 10) {
                Button {
                    if pageIndex < pages.count - 1 {
                        withAnimation(AppTheme.Motion.base) { pageIndex += 1 }
                    } else {
                        finish()
                    }
                } label: {
                    Text(pageIndex < pages.count - 1 ? "Next" : "Get started")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(AppPrimaryButtonStyle())
                .accessibilityIdentifier("welcomeTour.advance")
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    private func pageCard(_ page: TourPage) -> some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppTheme.surfacePrimary)
                    .frame(width: 76, height: 76)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    )
                Image(systemName: page.symbol)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.primary)
            }
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text(page.title)
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.2)
                    .multilineTextAlignment(.center)

                Text(page.body)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(pages.indices, id: \.self) { i in
                Button {
                    withAnimation(AppTheme.Motion.base) { pageIndex = i }
                } label: {
                    // Invisible 28×28 hit area around a 6pt dot — keeps the dot
                    // visually compact while still meeting Apple's touch-target
                    // guidance for a discrete action.
                    ZStack {
                        Color.clear.frame(width: 28, height: 28)
                        Circle()
                            .fill(i == pageIndex ? Color.primary : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                            .animation(AppTheme.Motion.fast, value: pageIndex)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Go to page \(i + 1) of \(pages.count)")
            }
        }
    }

    // MARK: - Finish

    /// One-shot completion path used by every dismissal source — Skip button,
    /// the explicit "Get started" CTA on the last page, or the corner Skip
    /// link. Flips `hasSeenWelcomeTour` so the onboarding chain advances and
    /// the tour never re-appears for this user.
    private func finish() {
        services.hasSeenWelcomeTour = true
    }
}

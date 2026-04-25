import SwiftUI
import UIKit

struct DefaultMailOnboardingView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        ZStack {
            AppTheme.backgroundTop.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.12))
                        .frame(width: 100, height: 100)
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(AppTheme.accent)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Email icon")

                Spacer().frame(height: 24)

                Text("Make Todus your mail app")
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                Spacer().frame(height: 12)

                Text("Tapping any email link — in Safari, Notes, or Messages — can open it here once Todus is selected as your default mail app.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AppTheme.mutedText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer().frame(height: 28)

                VStack(spacing: 12) {
                    onboardingMessage(
                        text: "We can only open Todus in the Settings app. From there, go back to Settings, open Default Apps → Email, and choose Todus.",
                        tint: AppTheme.mutedText
                    )

                    Button {
                        openDefaultAppsSettings()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "gear")
                            Text("Open Todus Settings")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(AppPrimaryButtonStyle())

                    Button {
                        services.hasConfiguredDefaultMailPrompt = true
                    } label: {
                        Text("Done, I've set it")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    Button {
                        services.hasConfiguredDefaultMailPrompt = true
                    } label: {
                        Text("Skip, keep my current app")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppTheme.mutedText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Skip setting Todus as the default mail app")
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .padding(.vertical, 32)
        }
    }

    private func openDefaultAppsSettings() {
        // `App-prefs:` and other private scheme URLs are not in LSApplicationQueriesSchemes,
        // can require undocumented entitlements, and risk App Review. Users can still open
        // Settings → Todus from this screen; the copy above explains Default Apps.
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
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

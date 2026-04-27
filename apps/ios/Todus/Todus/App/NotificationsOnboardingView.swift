import SwiftUI

struct NotificationsOnboardingView: View {
    @Environment(AppServices.self) private var services
    @State private var isRequesting = false
    @State private var requestResult: Bool? = nil

    var body: some View {
        ZStack {
            AppTheme.backgroundTop.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Notifications")

                Spacer().frame(height: 24)

                Text("Stay on top of it all")
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                Spacer().frame(height: 12)

                Text("Get notified about new emails, tasks due today, AI replies, and reminders — without having to check the app.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AppTheme.mutedText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer().frame(height: 28)

                VStack(spacing: 12) {
                    notificationFeatureRows

                    Spacer().frame(height: 4)

                    if let result = requestResult {
                        onboardingMessage(
                            text: result
                                ? "Notifications are on. Fine-tune them any time in Settings."
                                : "Notifications are off. You can enable them later in Settings → Notifications.",
                            tint: result ? .green : AppTheme.mutedText
                        )

                        Button {
                            services.hasConfiguredNotificationsPrompt = true
                        } label: {
                            Text("Continue")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(AppPrimaryButtonStyle())
                    } else {
                        onboardingMessage(
                            text: "We only ask once. You can turn each type on or off later in Settings.",
                            tint: AppTheme.mutedText
                        )

                        Button {
                            isRequesting = true
                            Task {
                                defer { isRequesting = false }
                                let granted = await services.notificationService.requestPermission()
                                requestResult = granted
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                if isRequesting {
                                    ButtonInlineProgressView()
                                }
                                Text(isRequesting ? "Requesting…" : "Enable Notifications")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(AppPrimaryButtonStyle())
                        .disabled(isRequesting)

                        Button {
                            services.hasConfiguredNotificationsPrompt = true
                        } label: {
                            Text("Skip, decide later")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppTheme.mutedText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Skip enabling notifications for now")
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .padding(.vertical, 32)
        }
    }

    private var notificationFeatureRows: some View {
        VStack(spacing: 0) {
            notificationRow(
                icon: "envelope.fill",
                title: "New emails",
                subtitle: "Incoming messages from your connected accounts"
            )
            Divider().padding(.leading, 52)
            notificationRow(
                icon: "checkmark.square.fill",
                title: "Task reminders",
                subtitle: "1 hour before a task is due and a daily digest"
            )
            Divider().padding(.leading, 52)
            notificationRow(
                icon: "sparkles",
                title: "AI responses",
                subtitle: "When Todus AI replies while you're away"
            )
            Divider().padding(.leading, 52)
            notificationRow(
                icon: "calendar",
                title: "Calendar events",
                subtitle: "Reminders for upcoming meetings and events"
            )
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }

    private func notificationRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28, height: 28)
                .background(AppTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
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

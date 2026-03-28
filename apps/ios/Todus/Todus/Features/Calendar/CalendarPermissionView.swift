import SwiftUI

/// Shown when the user has denied or not yet granted calendar access.
/// Visual style matches GmailOnboardingView / EmailConnectView for consistency.
struct CalendarPermissionView: View {
    @Environment(AppServices.self) private var services
    @State private var requestedAccess = false

    var body: some View {
        ZStack {
            AppTheme.backgroundTop.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                AppleCalendarIconView(size: 88)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Calendar icon")

                Spacer().frame(height: 24)

                Text("Calendar Access Required")
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                Spacer().frame(height: 12)

                Text("Allow access to your calendar\nto view and create events.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AppTheme.mutedText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer().frame(height: 40)

                // Show "Allow Access" if not yet determined, "Open Settings" if previously denied
                if services.calendarService.authorizationStatus() == .notDetermined && !requestedAccess {
                    Button {
                        Task {
                            requestedAccess = true
                            _ = await services.calendarService.requestAccess()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            AppleCalendarIconView(size: 20)
                            Text("Allow Access")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .padding(.horizontal, 24)
                    .accessibilityHint("Grant calendar access")
                } else {
                    // Permission was denied — user must grant in iOS Settings
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "gear")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Open Settings")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .padding(.horizontal, 24)

                    Spacer().frame(height: 16)

                    Text("You can enable calendar access in\nSettings → Privacy & Security → Calendars")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.mutedText)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding(.vertical, 32)
        }
    }
}

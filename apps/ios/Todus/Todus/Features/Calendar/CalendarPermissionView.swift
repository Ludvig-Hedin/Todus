import EventKit
import SwiftUI

/// Shown when the user has denied or not yet granted calendar access.
/// Visual style matches GmailOnboardingView / EmailConnectView for consistency.
struct CalendarPermissionView: View {
    @Environment(AppServices.self) private var services
    @State private var isRequesting = false

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

                Text(secondaryCopy)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AppTheme.mutedText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer().frame(height: 40)

                if services.calendarService.canReadEvents() {
                    ButtonInlineProgressView(tint: .primary, side: AppTheme.Metrics.buttonInlineSpinner)
                    Text("Loading calendar…")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.mutedText)
                    Spacer().frame(height: 12)
                } else if shouldShowAllowAccess {
                    Button {
                        Task {
                            isRequesting = true
                            defer { isRequesting = false }
                            _ = await services.calendarService.requestAccess()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if isRequesting {
                                ButtonInlineProgressView()
                            } else {
                                AppleCalendarIconView(size: 20)
                            }
                            Text(isRequesting ? "Connecting…" : "Allow Access")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .padding(.horizontal, 24)
                    .disabled(isRequesting)
                    .accessibilityHint("Grant calendar access")
                } else {
                    // Denied, restricted, or (iOS 17+) write-only — need Settings for full read access
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

    private var shouldShowAllowAccess: Bool {
        if needsSettingsRoute { return false }
        return services.calendarService.authorizationStatus() == .notDetermined
    }

    /// User must use Settings: denied, restricted, or write-only (Todus needs read access).
    private var needsSettingsRoute: Bool {
        let s = services.calendarService.authorizationStatus()
        switch s {
        case .denied, .restricted: return true
        default: break
        }
        if #available(iOS 17.0, *) {
            return s == .writeOnly
        }
        return false
    }

    private var secondaryCopy: String {
        if #available(iOS 17.0, *), services.calendarService.authorizationStatus() == .writeOnly {
            return "Todus needs full calendar access to show your events. Choose “Full Access” in Settings for this app."
        }
        return "Allow access to your calendar\nto view and create events."
    }
}

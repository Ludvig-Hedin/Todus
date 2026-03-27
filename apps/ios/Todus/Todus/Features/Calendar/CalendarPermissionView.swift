import SwiftUI

/// Shown when the user has denied or not yet granted calendar access.
/// Follows the same pattern as EmailConnectView — centered icon, message, action button.
struct CalendarPermissionView: View {
    @Environment(AppServices.self) private var services
    @State private var requestedAccess = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(AppTheme.subtleText)

            VStack(spacing: 8) {
                Text("Calendar Access Required")
                    .font(.system(size: 22, weight: .bold))

                Text("Allow access to your calendar\nto view and create events.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.subtleText)
                    .multilineTextAlignment(.center)
            }

            // Show "Open Settings" if previously denied, "Allow Access" if not yet determined
            if services.calendarService.authorizationStatus() == .notDetermined && !requestedAccess {
                Button {
                    Task {
                        requestedAccess = true
                        _ = await services.calendarService.requestAccess()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Allow Access")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
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
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)

                Text("You can enable calendar access in\nSettings → Privacy & Security → Calendars")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
            Spacer()
        }
    }
}

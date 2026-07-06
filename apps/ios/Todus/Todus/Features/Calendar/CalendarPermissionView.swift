import EventKit
import SwiftUI

/// Shown when the user has denied or not yet granted calendar access.
/// Visual style matches GmailOnboardingView / EmailConnectView for consistency.
struct CalendarPermissionView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @State private var isRequesting = false
    /// Tracked locally so the view re-renders after the user returns from Settings
    /// or the system permission alert. Reading
    /// `EKEventStore.authorizationStatus(for:)` on every body call is cheap but
    /// SwiftUI won't re-run body without an observable dependency — this state
    /// is bumped from `.onReceive` / `.onChange(scenePhase)` to force a refresh.
    @State private var authStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

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

                if canReadEvents {
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
                            // CalendarService posts `todusCalendarAuthorizationDidChange`
                            // after the system prompt completes — refresh locally too
                            // in case the notification fires before this Task resumes.
                            await MainActor.run {
                                authStatus = EKEventStore.authorizationStatus(for: .event)
                            }
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
                        openSystemSettings()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "gear")
                                .font(.system(size: 16, weight: .semibold))
                            Text(canOpenSettings ? "Open Settings" : "Open Settings App")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .padding(.horizontal, 24)

                    Spacer().frame(height: 16)

                    Text(settingsHintCopy)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.mutedText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()
            }
            .padding(.vertical, 32)
        }
        .onAppear {
            authStatus = EKEventStore.authorizationStatus(for: .event)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                authStatus = EKEventStore.authorizationStatus(for: .event)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .todusCalendarAuthorizationDidChange)) { _ in
            authStatus = EKEventStore.authorizationStatus(for: .event)
        }
    }

    // MARK: - Authorization-derived state

    /// Mirrors `CalendarService.canReadEvents()` but reads the locally tracked
    /// `authStatus` so SwiftUI re-renders when the permission changes.
    private var canReadEvents: Bool {
        if #available(iOS 17.0, *) {
            return authStatus == .fullAccess
        } else {
            return authStatus == .authorized
        }
    }

    private var canOpenSettings: Bool {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            return UIApplication.shared.canOpenURL(url)
        }
        return false
    }

    private var settingsHintCopy: String {
        if #available(iOS 17.0, *) {
            return "Enable “Full Access” in Settings → Privacy & Security → Calendars → Todus."
        }
        return "You can enable calendar access in\nSettings → Privacy & Security → Calendars."
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }

    private var shouldShowAllowAccess: Bool {
        if needsSettingsRoute { return false }
        return authStatus == .notDetermined
    }

    /// User must use Settings: denied, restricted, or write-only (Todus needs read access).
    private var needsSettingsRoute: Bool {
        switch authStatus {
        case .denied, .restricted: return true
        default: break
        }
        if #available(iOS 17.0, *) {
            return authStatus == .writeOnly
        }
        return false
    }

    private var secondaryCopy: String {
        if #available(iOS 17.0, *), authStatus == .writeOnly {
            return "Todus needs full calendar access to show your events. Choose “Full Access” in Settings for this app."
        }
        if #available(iOS 17.0, *), authStatus == .notDetermined {
            // Proactive heads-up before the system prompt appears — iOS 17+ offers
            // a "Write Only" option that would leave events invisible in Todus, so
            // steer the user toward "Full Access" up front instead of only
            // reacting to it after the fact (see the `.writeOnly` branch above).
            return "Allow access to your calendar to view and create events. If asked, choose “Full Access.”"
        }
        return "Allow access to your calendar\nto view and create events."
    }
}

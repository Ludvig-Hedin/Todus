import SwiftUI

/// Settings → Calendar Accounts. Mirrors the "Connected Services" section
/// structurally, but each Google account expands into a list of its calendars
/// with per-calendar toggles + a "Default for new events" radio.
struct CalendarAccountsView: View {
    @Environment(AppServices.self) private var services

    @State private var appleSources: [CalendarSource] = []
    @State private var isLoading = false

    var body: some View {
        List {
            appleSection

            ForEach(googleConnections, id: \.id) { conn in
                googleSection(conn: conn)
            }

            Section {
                Button {
                    // Same flow as the "Add Gmail account" CTA in Connected Services.
                    services.showsSettings = false // pop back if needed
                    NotificationCenter.default.post(name: .todusRequestConnectGmail, object: nil)
                } label: {
                    Label("Add Calendar Account", systemImage: "plus.circle.fill")
                }
            } footer: {
                Text("Adding a Gmail account also imports its calendars.")
                    .font(.caption)
            }

            Section {
                Toggle(isOn: Binding(
                    get: { services.calendarPreferences.preferGoogleOverAppleDuplicates },
                    set: { newValue in
                        var prefs = services.calendarPreferences
                        prefs.preferGoogleOverAppleDuplicates = newValue
                        services.calendarPreferences = prefs
                        Task { await services.saveCalendarPreferences() }
                    }
                )) {
                    Text("Hide Apple-side Gmail duplicates")
                }
            } footer: {
                Text("When a Gmail account is also added in iOS Settings → Mail, EventKit shows the same events twice. Keeping this on prefers the connected Gmail copy.")
                    .font(.caption)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.sheetBackground)
        .navigationTitle("Calendar Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh(force: true) }
    }

    private var googleConnections: [ConnectionAccount] {
        services.connectionsService.connections.filter { $0.providerId == "google" }
    }

    @ViewBuilder
    private var appleSection: some View {
        if !appleSources.isEmpty {
            Section {
                ForEach(appleSources) { source in
                    sourceRow(source, accountKey: CalendarSourceIDPrefix.apple)
                }
            } header: {
                Text("On This iPhone")
            } footer: {
                Text("Edit calendar names and colors in the iOS Calendar app.")
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func googleSection(conn: ConnectionAccount) -> some View {
        let sources = services.googleCalendarService.sources(forConnectionId: conn.id)
        let scopeMissing = services.googleCalendarService.scopeMissingConnectionIds.contains(conn.id)
        let accountKey = "\(CalendarSourceIDPrefix.google):\(conn.id)"

        Section {
            if scopeMissing {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Reconnect to enable calendar editing.")
                        .font(.subheadline)
                    Spacer()
                    Button("Reconnect") {
                        NotificationCenter.default.post(
                            name: .todusRequestReconnectGmail,
                            object: nil,
                            userInfo: [TodusReconnectConnectionIdKey: conn.id]
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.vertical, 2)
            }

            if sources.isEmpty && !scopeMissing {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading calendars...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            ForEach(sources) { source in
                sourceRow(source, accountKey: accountKey)
            }
        } header: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: conn.displayColor as String?) ?? .accentColor)
                    .frame(width: 8, height: 8)
                Text(conn.email)
            }
        }
    }

    private func sourceRow(_ source: CalendarSource, accountKey: String) -> some View {
        let isVisible = !services.calendarPreferences.isHidden(source.id)
        let isDefault = services.calendarPreferences.defaultId(forAccountKey: accountKey) == source.id
        return HStack(spacing: 12) {
            Circle()
                .fill(source.color)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .font(.body)
                HStack(spacing: 6) {
                    if !source.isWritable {
                        Text("Subscribed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if isDefault {
                        Text("Default")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.18), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            Spacer(minLength: 8)

            if source.isWritable && isVisible {
                Button {
                    if isDefault {
                        services.setDefaultCalendar(nil, forAccountKey: accountKey)
                    } else {
                        services.setDefaultCalendar(source.id, forAccountKey: accountKey)
                    }
                } label: {
                    Image(systemName: isDefault ? "star.fill" : "star")
                        .foregroundStyle(isDefault ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set as default for new events")
            }

            // Visible "Show" label so the toggle is self-describing on its own —
            // sighted users previously saw only a bare knob (`.labelsHidden()`
            // with an empty label string).
            Toggle(
                "Show",
                isOn: Binding(
                    get: { isVisible },
                    set: { _ in services.toggleCalendarVisibility(source.id) }
                )
            )
            .font(.caption)
            .fixedSize()
            .accessibilityLabel("Show \(source.displayName)")
        }
        .padding(.vertical, 2)
    }

    private func refresh(force: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        appleSources = await services.calendarService.listAppleSources()
        if services.connectionsService.connections.isEmpty {
            await services.connectionsService.loadConnections()
        }
        let googleConns = services.connectionsService.connections.filter { $0.providerId == "google" }
        if force || services.googleCalendarService.isStale {
            await services.googleCalendarService.refresh(googleConnections: googleConns)
        }
    }
}

extension Notification.Name {
    /// Posted by Settings → Calendar Accounts when the "Add Calendar Account"
    /// CTA is tapped. The host SettingsView observes and runs `performConnectGmail()`.
    static let todusRequestConnectGmail = Notification.Name("TodusRequestConnectGmail")
    /// Posted by the reconnect banner; userInfo carries the connection id.
    static let todusRequestReconnectGmail = Notification.Name("TodusRequestReconnectGmail")
}

let TodusReconnectConnectionIdKey = "connectionId"

private extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 {
            s = s.map { "\($0)\($0)" }.joined()
        }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}

import SwiftUI

/// macOS Settings → Calendars row. Lists Apple sources first, then expandable
/// rows per Google connection with per-calendar visibility toggles + a
/// "default-for-new-events" star and a "Hide Apple-side Gmail duplicates" switch.
struct MacCalendarAccountsList: View {
    @Environment(MacAppServices.self) private var services

    @State private var appleSources: [CalendarSource] = []
    @State private var isLoading = false
    @State private var expandedConnections: Set<String> = []
    /// Reflects a pending "Add Calendar Account" tap so the button shows a
    /// spinner while the OAuth window is being prepared. The post is
    /// fire-and-forget, so we briefly self-clear after a short delay rather
    /// than awaiting a completion signal that doesn't exist.
    @State private var isConnecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !appleSources.isEmpty {
                accountHeader(title: "On This Mac", dotColor: nil)
                ForEach(appleSources) { source in
                    sourceRow(source, accountKey: CalendarSourceIDPrefix.apple)
                }
            }

            ForEach(googleConnections, id: \.id) { conn in
                connectionRow(conn)
            }

            Divider()

            HStack {
                Toggle(isOn: Binding(
                    get: { services.calendarPreferences.preferGoogleOverAppleDuplicates },
                    set: { newValue in
                        var prefs = services.calendarPreferences
                        prefs.preferGoogleOverAppleDuplicates = newValue
                        services.calendarPreferences = prefs
                        Task { await services.saveCalendarPreferences() }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Hide Apple-side Gmail duplicates")
                            .font(.system(size: 12, weight: .medium))
                        Text("Prefer the connected Gmail copy when the same account also syncs through iOS.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                Spacer()
            }

            HStack {
                Button {
                    isConnecting = true
                    NotificationCenter.default.post(name: .todusRequestConnectGmail, object: nil)
                    // The OAuth handoff is asynchronous and runs in a separate
                    // window we don't have a callback for; reset the spinner
                    // after a brief grace period so the user has visible
                    // feedback that the click registered.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        isConnecting = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isConnecting {
                            ProgressView()
                                .controlSize(.small)
                                .progressViewStyle(.circular)
                        }
                        Label(isConnecting ? "Connecting…" : "Add Calendar Account",
                              systemImage: "plus.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isConnecting)
                Spacer()
            }
        }
        .padding(12)
        .task { await refresh() }
    }

    private var googleConnections: [ConnectionAccount] {
        services.connectionsService.connections.filter { $0.providerId == "google" }
    }

    private func connectionRow(_ conn: ConnectionAccount) -> some View {
        let scopeMissing = services.googleCalendarService.scopeMissingConnectionIds.contains(conn.id)
        let sources = services.googleCalendarService.sources(forConnectionId: conn.id)
        let isExpanded = expandedConnections.contains(conn.id)
        let dotColor = Color(hex: conn.displayColor) ?? .accentColor
        let accountKey = "\(CalendarSourceIDPrefix.google):\(conn.id)"

        return VStack(alignment: .leading, spacing: 6) {
            Button {
                if isExpanded {
                    expandedConnections.remove(conn.id)
                } else {
                    expandedConnections.insert(conn.id)
                }
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(dotColor).frame(width: 10, height: 10)
                    Text(conn.email).font(.system(size: 13, weight: .medium))
                    Spacer()
                    if scopeMissing {
                        Text("Reconnect").font(.caption).foregroundStyle(.orange)
                    }
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                if scopeMissing {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Reconnect to enable calendar editing.")
                            .font(.caption)
                        Spacer()
                        Button("Reconnect") {
                            NotificationCenter.default.post(
                                name: .todusRequestReconnectGmail,
                                object: nil,
                                userInfo: [TodusReconnectConnectionIdKey: conn.id]
                            )
                        }
                    }
                    .padding(.leading, 18)
                }
                ForEach(sources) { source in
                    sourceRow(source, accountKey: accountKey)
                        .padding(.leading, 18)
                }
                if sources.isEmpty && !scopeMissing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Loading calendars…").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.leading, 18)
                }
            }
        }
    }

    private func sourceRow(_ source: CalendarSource, accountKey: String) -> some View {
        let isVisible = !services.calendarPreferences.isHidden(source.id)
        let isDefault = services.calendarPreferences.defaultId(forAccountKey: accountKey) == source.id
        return HStack(spacing: 10) {
            Toggle(
                "",
                isOn: Binding(
                    get: { isVisible },
                    set: { _ in services.toggleCalendarVisibility(source.id) }
                )
            )
            .labelsHidden()
            .toggleStyle(.checkbox)

            Circle().fill(source.color).frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 1) {
                Text(source.displayName).font(.system(size: 13))
                if !source.isWritable {
                    Text("Subscribed").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }

            Spacer()

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
                .help(isDefault ? "Default for new events" : "Make default for new events")
            }
        }
    }

    private func accountHeader(title: String, dotColor: Color?) -> some View {
        HStack(spacing: 6) {
            if let dotColor {
                Circle().fill(dotColor).frame(width: 8, height: 8)
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        appleSources = await services.calendarService.listAppleSources()
        if services.connectionsService.connections.isEmpty {
            await services.connectionsService.loadConnections()
        }
        let googleConns = services.connectionsService.connections.filter { $0.providerId == "google" }
        if services.googleCalendarService.isStale {
            await services.googleCalendarService.refresh(googleConnections: googleConns)
        }
    }
}

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

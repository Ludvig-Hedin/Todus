import SwiftUI

/// macOS popover variant of the calendar source picker. Shown from the
/// MacCalendarView toolbar button. Lists Apple sources first, then one
/// section per Google connection. Each row toggles visibility.
struct MacCalendarSourcePicker: View {
    @Environment(MacAppServices.self) private var services

    var onAddAccount: (() -> Void)?

    @State private var appleSources: [CalendarSource] = []
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Calendars")
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !appleSources.isEmpty {
                        sectionHeader("On This Mac")
                        ForEach(appleSources) { source in
                            sourceRow(source)
                            Divider().padding(.leading, 30)
                        }
                    }

                    ForEach(googleConnections, id: \.id) { conn in
                        let sources = services.googleCalendarService.sources(forConnectionId: conn.id)
                        if !sources.isEmpty || services.googleCalendarService.scopeMissingConnectionIds.contains(conn.id) {
                            sectionHeader(conn.email, dotColor: Color(hex: conn.displayColor) ?? .accentColor)
                            if services.googleCalendarService.scopeMissingConnectionIds.contains(conn.id) {
                                Text("Reconnect to enable calendar editing.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                            }
                            ForEach(sources) { source in
                                sourceRow(source)
                                Divider().padding(.leading, 30)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            Divider()

            Button {
                onAddAccount?()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Calendar Account")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .task { await refresh() }
        // Refresh when a new Google account is added while the popover is open
        // so the new connection appears without having to reopen the picker.
        .onChange(of: services.connectionsService.connections.count) { _, _ in
            Task { await refresh() }
        }
    }

    private var googleConnections: [ConnectionAccount] {
        services.connectionsService.connections.filter { $0.providerId == "google" }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, dotColor: Color? = nil) -> some View {
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
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func sourceRow(_ source: CalendarSource) -> some View {
        let isVisible = !services.calendarPreferences.isHidden(source.id)
        return HStack(spacing: 10) {
            Toggle(
                "",
                isOn: Binding(
                    get: { isVisible },
                    // Defer the mutation until after the current view-update
                    // pass so we don't trigger a write during a Binding setter
                    // (which can race with the dependent view rebuild and drop
                    // the toggle's first tap on macOS 15).
                    set: { _ in
                        Task { @MainActor in
                            services.toggleCalendarVisibility(source.id)
                        }
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.checkbox)

            Circle()
                .fill(source.color)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 1) {
                Text(source.displayName)
                    .font(.system(size: 13))
                if !source.isWritable {
                    Text("Subscribed")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
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

extension Notification.Name {
    static let todusRequestConnectGmail = Notification.Name("TodusRequestConnectGmail")
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

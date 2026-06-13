import SwiftUI

/// Quick-toggle popover/sheet listing every calendar source the user has,
/// grouped by account. Mirrors Apple Calendar's "Calendars" picker UX.
///
/// Top section: Apple (EventKit) calendars under "On This iPhone".
/// Then one section per Google connection, titled by email.
/// Footer: deep link into Settings → Calendar Accounts to add a new account.
struct CalendarSourcePickerView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    /// Set true when the parent presents this view as a sheet on iPhone.
    /// Adds a "Done" toolbar button.
    var isSheet: Bool = false

    /// Tap handler for "Add Calendar Account" → parent route to Settings.
    var onAddAccount: (() -> Void)?

    @State private var appleSources: [CalendarSource] = []
    @State private var isLoading = false

    var body: some View {
        Group {
            if isSheet {
                NavigationStack {
                    list
                        .navigationTitle("Calendars")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { dismiss() }
                            }
                        }
                }
            } else {
                list
                    .frame(minWidth: 320, idealWidth: 360, minHeight: 200, idealHeight: 480)
            }
        }
        .task { await refresh() }
    }

    private var googleSourceGroups: [(connection: ConnectionAccount, sources: [CalendarSource])] {
        services.connectionsService.connections
            .filter { $0.providerId == "google" }
            .map { conn in
                (conn, services.googleCalendarService.sources(forConnectionId: conn.id))
            }
    }

    private var hasAnySources: Bool {
        !appleSources.isEmpty || googleSourceGroups.contains { !$0.sources.isEmpty }
    }

    private var list: some View {
        List {
            if !appleSources.isEmpty {
                Section("On This iPhone") {
                    ForEach(appleSources) { source in
                        sourceRow(source)
                    }
                }
            }

            ForEach(googleSourceGroups, id: \.connection.id) { group in
                if !group.sources.isEmpty {
                    Section {
                        ForEach(group.sources) { source in
                            sourceRow(source)
                        }
                    } header: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hex: group.connection.displayColor as String?) ?? .accentColor)
                                .frame(width: 8, height: 8)
                            Text(group.connection.email)
                        }
                    } footer: {
                        if services.googleCalendarService.scopeMissingConnectionIds.contains(group.connection.id) {
                            Text("Reconnect to enable calendar editing for this account.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            if !hasAnySources && !isLoading {
                Section {
                    Text("No calendars yet. Connect a Gmail account to import its calendars, or grant Apple Calendar access in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    onAddAccount?()
                    if isSheet { dismiss() }
                } label: {
                    Label("Add Calendar Account", systemImage: "plus.circle.fill")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.sheetBackground)
        .refreshable { await refresh(force: true) }
        .overlay(alignment: .top) {
            if isLoading {
                ProgressView().padding(.top, 8)
            }
        }
    }

    private func sourceRow(_ source: CalendarSource) -> some View {
        let isVisible = !services.calendarPreferences.isHidden(source.id)
        return HStack(spacing: 12) {
            Circle()
                .fill(source.color)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .font(.body)
                if !source.isWritable {
                    Text("Subscribed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Toggle(
                "",
                isOn: Binding(
                    get: { isVisible },
                    set: { _ in services.toggleCalendarVisibility(source.id) }
                )
            )
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    private func refresh(force: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        appleSources = await services.calendarService.listAppleSources()

        // Make sure connections are loaded before refreshing google sources.
        if services.connectionsService.connections.isEmpty {
            await services.connectionsService.loadConnections()
        }
        let googleConns = services.connectionsService.connections.filter { $0.providerId == "google" }
        if force || services.googleCalendarService.isStale {
            await services.googleCalendarService.refresh(googleConnections: googleConns)
        }
    }
}

private extension Color {
    /// Permissive `#RRGGBB` / `#RGB` initializer used by the picker.
    init?(hex: String?) {
        guard let hex else { return nil }
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 {
            // Expand "abc" → "aabbcc"
            s = s.map { "\($0)\($0)" }.joined()
        }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}

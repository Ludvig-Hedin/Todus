import SwiftUI
import AppKit

// MARK: - Meetings Hub (Split List + Detail)

struct MacMeetingsView: View {
    @Environment(MacAppServices.self) private var services

    @State private var selectedMeetingId: String? = nil
    @State private var searchText = ""
    @State private var statusFilter: String? = nil
    @State private var rotationAngle = 0.0
    /// Watchdog that force-resets `isSyncing` if a sync hangs (e.g. silent network failure).
    @State private var syncTimeoutTask: Task<Void, Never>? = nil

    private func updateSyncRotation(isSyncing: Bool) {
        if isSyncing {
            rotationAngle = 0
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                rotationAngle = 0
            }
        }
    }

    /// Schedule a 30s timeout that force-resets the spinner if `isSyncing` is still true.
    /// Guards against a stuck spinner when the underlying sync swallows an error.
    private func scheduleSyncTimeout() {
        syncTimeoutTask?.cancel()
        syncTimeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            if services.meetingsService.isSyncing {
                services.meetingsService.isSyncing = false
            }
        }
    }

    var body: some View {
        HSplitView {
            // Left: meeting list
            meetingList
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 400)

            // Right: meeting detail or empty state
            if let meetingId = selectedMeetingId {
                MacMeetingDetailView(meetingId: meetingId)
                    .id(meetingId)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await services.meetingsService.loadMeetings()
        }
        .onAppear {
            updateSyncRotation(isSyncing: services.meetingsService.isSyncing)
        }
        .onChange(of: services.meetingsService.isSyncing) { _, isSyncing in
            updateSyncRotation(isSyncing: isSyncing)
            // If the service flips to not-syncing on its own, cancel the watchdog.
            if !isSyncing { syncTimeoutTask?.cancel() }
        }
        // Refresh the meetings list whenever the window regains focus, so users
        // see new entries that were captured while Todus was in the background.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await services.meetingsService.loadMeetings(
                    status: statusFilter,
                    search: searchText.isEmpty ? nil : searchText
                )
            }
        }
    }

    // MARK: - List

    private var meetingList: some View {
        VStack(spacing: 0) {
            // Header with sync button
            HStack {
                Text("Meetings")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.8))

                Spacer()

                Button {
                    scheduleSyncTimeout()
                    Task { await services.meetingsService.syncFromCalendar() }
                } label: {
                    Image(systemName: services.meetingsService.isSyncing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(rotationAngle))
                }
                .buttonStyle(.plain)
                .macClickablePointer()
                .help("Sync from Google Calendar")
                .disabled(services.meetingsService.isSyncing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Search meetings...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            .onChange(of: searchText) { _, newValue in
                Task {
                    await services.meetingsService.loadMeetings(
                        status: statusFilter,
                        search: newValue.isEmpty ? nil : newValue
                    )
                }
            }

            Divider()

            // Status filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    filterPill("All", value: nil)
                    filterPill("Scheduled", value: "scheduled")
                    filterPill("Ready", value: "ready")
                    filterPill("Failed", value: "failed")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }

            Divider()

            // Meeting rows
            if services.meetingsService.isLoading {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Spacer()
            } else if let errorMessage = services.meetingsService.loadError,
                      services.meetingsService.meetings.isEmpty {
                // Show error state only when there is nothing to display
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundStyle(.orange)
                    Text("Failed to load meetings")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Button("Retry") {
                        Task { await services.meetingsService.loadMeetings() }
                    }
                    .controlSize(.small)
                }
                Spacer()
            } else if services.meetingsService.meetings.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No meetings")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Sync your calendar to import meetings. They'll be recorded automatically when possible.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(groupedMeetings) { group in
                            Section {
                                ForEach(group.meetings) { meeting in
                                    MacMeetingRowView(
                                        meeting: meeting,
                                        isSelected: selectedMeetingId == meeting.id
                                    ) {
                                        selectedMeetingId = meeting.id
                                    }
                                }
                            } header: {
                                Text(group.title)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .tracking(0.5)
                                    .textCase(.uppercase)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.top, 12)
                                    .padding(.bottom, 4)
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .background(MacTheme.contentBackground)
    }

    private var emptyDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "video")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Select a meeting to view details")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacTheme.contentBackground)
    }

    // MARK: - Helpers

    private func filterPill(_ label: String, value: String?) -> some View {
        let isActive = statusFilter == value
        return Button {
            statusFilter = value
            Task {
                await services.meetingsService.loadMeetings(
                    status: value,
                    search: searchText.isEmpty ? nil : searchText
                )
            }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .primary : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(isActive ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                )
        }
        .buttonStyle(.plain)
        .macClickablePointer()
    }

    // Group meetings by time period — future meetings appear as "Upcoming"
    private var groupedMeetings: [MeetingGroup] {
        let calendar = Calendar.current
        let today = Date()
        let todayStart = calendar.startOfDay(for: today)
        var todayItems: [MeetingItem] = []
        var thisWeekItems: [MeetingItem] = []
        var upcomingItems: [MeetingItem] = []
        var earlierItems: [MeetingItem] = []

        for m in services.meetingsService.meetings {
            if calendar.isDateInToday(m.startsAt) {
                todayItems.append(m)
            } else if m.startsAt > todayStart {
                // Future: split between this week and beyond
                if calendar.isDate(m.startsAt, equalTo: today, toGranularity: .weekOfYear) {
                    thisWeekItems.append(m)
                } else {
                    upcomingItems.append(m)
                }
            } else {
                earlierItems.append(m)
            }
        }

        var groups: [MeetingGroup] = []
        if !todayItems.isEmpty { groups.append(MeetingGroup(title: "Today", meetings: todayItems)) }
        if !thisWeekItems.isEmpty { groups.append(MeetingGroup(title: "This Week", meetings: thisWeekItems)) }
        if !upcomingItems.isEmpty { groups.append(MeetingGroup(title: "Upcoming", meetings: upcomingItems)) }
        if !earlierItems.isEmpty { groups.append(MeetingGroup(title: "Earlier", meetings: earlierItems)) }
        return groups
    }
}

private struct MeetingGroup: Identifiable {
    let title: String
    let meetings: [MeetingItem]
    var id: String { title }
}

// MARK: - Meeting Row

struct MacMeetingRowView: View {
    let meeting: MeetingItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Status icon
                Image(systemName: statusIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(statusColor)
                    .frame(width: 20, height: 20)
                    .background(statusColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(meeting.startsAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if meeting.aiSummary != nil {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(.purple.opacity(0.6))
                }

                // Status badge
                Text(statusLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.1), in: Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .macClickablePointer()
    }

    private var statusIcon: String {
        switch meeting.status {
        case "scheduled": "calendar"
        case "bot_joining", "processing": "arrow.triangle.2.circlepath"
        case "recording": "record.circle"
        case "ready": "checkmark.circle"
        case "failed": "exclamationmark.triangle"
        case "cancelled": "xmark.circle"
        default: "circle"
        }
    }

    private var statusLabel: String {
        switch meeting.status {
        case "scheduled": "Scheduled"
        case "bot_joining": "Starting"
        case "recording": "Recording"
        case "processing": "Processing"
        case "ready": "Ready"
        case "failed": "Failed"
        case "cancelled": "Cancelled"
        default: meeting.status.capitalized
        }
    }

    private var statusColor: Color {
        switch meeting.status {
        case "scheduled": .primary
        case "bot_joining", "processing": .orange
        case "recording": .red
        case "ready": .green
        case "failed": .red
        case "cancelled": .gray
        default: .secondary
        }
    }
}

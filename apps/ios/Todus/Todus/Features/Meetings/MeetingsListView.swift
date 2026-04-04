import SwiftUI

/// Meetings list — time-grouped sections with sync, search, and status badges.
struct MeetingsListView: View {
    @Environment(AppServices.self) private var services

    @State private var searchText = ""
    @State private var searchDebounceTask: Task<Void, Never>? = nil

    var body: some View {
        // Use same layout pattern as HomeView / EmailInboxView:
        // AppTopHeader pinned at top, list content below. Hides system nav bar
        // so title appears in the same position as every other tab.
        ZStack {
            AppTheme.backgroundTop.ignoresSafeArea()

            VStack(spacing: 0) {
                // Pinned header — matches the same AppTopHeader pattern used on
                // Home, Email, and Tasks so the title sits at the same vertical position.
                AppTopHeader(title: "Meetings")
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                listContent
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: String.self) { meetingId in
            MeetingDetailView(meetingId: meetingId)
        }
        .task {
            await services.meetingsService.loadMeetings()
        }
        .onDisappear {
            searchDebounceTask?.cancel()
            searchDebounceTask = nil
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if services.meetingsService.isLoading && services.meetingsService.meetings.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = services.meetingsService.loadError, services.meetingsService.meetings.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Could not load meetings")
                    .font(.headline)
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Retry") {
                    Task {
                        await services.meetingsService.loadMeetings(
                            search: searchText.isEmpty ? nil : searchText
                        )
                    }
                }
                .buttonStyle(AppPrimaryButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if services.meetingsService.meetings.isEmpty {
            emptyState
        } else {
            List {
                ForEach(groupedSections) { section in
                    Section(section.title) {
                        ForEach(section.meetings) { meeting in
                            NavigationLink(value: meeting.id) {
                                MeetingRowView(meeting: meeting)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            // Pull-to-refresh syncs from Google Calendar — replaces the old toolbar button
            .refreshable {
                await services.meetingsService.syncFromCalendar()
            }
            .searchable(text: $searchText, prompt: "Search meetings")
            .onChange(of: searchText) { _, newValue in
                searchDebounceTask?.cancel()
                searchDebounceTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    await services.meetingsService.loadMeetings(
                        search: newValue.isEmpty ? nil : newValue
                    )
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("No meetings")
                .font(.headline)

            Text("Sync your Google Calendar to import meetings. They'll be recorded automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                Task { await services.meetingsService.syncFromCalendar() }
            } label: {
                Label("Sync Calendar", systemImage: "arrow.clockwise")
            }
            .buttonStyle(AppPrimaryButtonStyle())
            .disabled(services.meetingsService.isSyncing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Group by time period
    private var groupedSections: [MeetingSection] {
        let calendar = Calendar.current
        let today = Date()
        var todayItems: [MeetingItem] = []
        var thisWeekItems: [MeetingItem] = []
        var earlierItems: [MeetingItem] = []
        var upcomingItems: [MeetingItem] = []

        for m in services.meetingsService.meetings {
            if calendar.isDateInToday(m.startsAt) {
                todayItems.append(m)
            } else if calendar.isDate(m.startsAt, equalTo: today, toGranularity: .weekOfYear)
                && calendar.isDate(m.startsAt, equalTo: today, toGranularity: .year) {
                thisWeekItems.append(m)
            } else if m.startsAt > today {
                upcomingItems.append(m)
            } else {
                earlierItems.append(m)
            }
        }

        var sections: [MeetingSection] = []
        if !todayItems.isEmpty { sections.append(MeetingSection(title: "Today", meetings: todayItems)) }
        if !thisWeekItems.isEmpty { sections.append(MeetingSection(title: "This Week", meetings: thisWeekItems)) }
        if !upcomingItems.isEmpty { sections.append(MeetingSection(title: "Upcoming", meetings: upcomingItems)) }
        if !earlierItems.isEmpty { sections.append(MeetingSection(title: "Earlier", meetings: earlierItems)) }
        return sections
    }
}

private struct MeetingSection: Identifiable {
    let title: String
    let meetings: [MeetingItem]
    var id: String { title }
}

// MARK: - Row

struct MeetingRowView: View {
    let meeting: MeetingItem

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: statusIcon)
                .font(.system(size: 14))
                .foregroundStyle(statusColor)
                .frame(width: 28, height: 28)
                .background(statusColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(meeting.title)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)

                Text(meeting.startsAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if meeting.aiSummary != nil {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(.purple.opacity(0.7))
                    .accessibilityLabel("AI summary available")
            }

            Text(statusLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.1), in: Capsule())
        }
        .padding(.vertical, 4)
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
        case "scheduled": .blue
        case "bot_joining", "processing": .orange
        case "recording": .red
        case "ready": .green
        case "failed": .red
        case "cancelled": .gray
        default: .secondary
        }
    }
}

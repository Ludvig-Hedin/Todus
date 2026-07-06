import SwiftUI

/// Meetings list — time-grouped sections with sync, search, and status badges.
struct MeetingsListView: View {
    @Environment(AppServices.self) private var services

    @State private var searchText = ""
    @State private var searchDebounceTask: Task<Void, Never>? = nil
    @State private var headerHeight: CGFloat = 60
    private let scrimTail: CGFloat = 32

    var body: some View {
        ZStack(alignment: .top) {
            AppTheme.backgroundTop.ignoresSafeArea()

            listContent
                .safeAreaInset(edge: .top) {
                    Color.clear.frame(height: headerHeight + scrimTail)
                }

            VStack(spacing: 0) {
                AppTopHeader(title: "Meetings")
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 4)
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                headerHeight = height
            }
            .pageHeaderScrim(color: AppTheme.backgroundTop, scrimHeight: headerHeight + scrimTail)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
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
                // Inline error banner — shown even when meetings are already loaded so
                // a failed sync doesn't silently disappear.
                if let error = services.meetingsService.loadError {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.subheadline)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                ForEach(groupedSections) { section in
                    Section(section.title) {
                        ForEach(section.meetings) { meeting in
                            NavigationLink(value: meeting.id) {
                                MeetingRowView(meeting: meeting)
                            }
                        }
                    }
                }
                if let synced = services.meetingsService.lastSyncedAt {
                    Section {
                        Button {
                            Task { await services.meetingsService.syncFromCalendar() }
                        } label: {
                            HStack {
                                Spacer()
                                if services.meetingsService.isSyncing {
                                    ButtonInlineProgressView(tint: .secondary, side: AppTheme.Metrics.compactInlineSpinner)
                                } else {
                                    Label(syncedAgoText(synced), systemImage: "arrow.clockwise")
                                        .font(.caption2)
                                        .foregroundStyle(.quaternary)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(services.meetingsService.isSyncing)
                        .accessibilityLabel("Sync calendar")
                        .accessibilityHint(syncedAgoText(synced))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.insetGrouped)
            // Reveal the AppTheme.backgroundTop layer behind the List instead of
            // the system grouped background (pure black in dark mode).
            .scrollContentBackground(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { old, new in
                let delta = new - old
                if delta > 8 && new > 40 {
                    withAnimation(.easeOut(duration: 0.2)) { services.hideTabBar = true }
                } else if delta < -8 {
                    withAnimation(.easeOut(duration: 0.2)) { services.hideTabBar = false }
                }
            }
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

            Text("Sync your Google Calendar to import meetings. Enable auto-record in settings to capture them automatically.")
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

    private var displayStatus: String {
        if meeting.status == "scheduled" {
            let end = meeting.endsAt ?? meeting.startsAt.addingTimeInterval(3600)
            if end < Date() { return "past" }
        }
        return meeting.status
    }

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
                    .help(meeting.title)
                    .accessibilityLabel(meeting.title)

                HStack(spacing: 4) {
                    Text(relativeTime(meeting.startsAt))
                    Text("·")
                    Text(meeting.startsAt.formatted(.dateTime.hour().minute()))
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }

            Spacer()

            if meeting.aiSummary != nil {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .accessibilityLabel("AI summary available")
            }

            Text(statusLabel)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch displayStatus {
        case "scheduled": "calendar"
        case "past": "clock.badge.xmark"
        case "bot_joining", "processing": "arrow.triangle.2.circlepath"
        case "recording": "record.circle"
        case "ready": "checkmark.circle"
        case "failed": "exclamationmark.triangle"
        case "cancelled": "xmark.circle"
        default: "circle"
        }
    }

    private var statusLabel: String {
        switch displayStatus {
        case "scheduled": "Scheduled"
        case "past": "Past"
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
        switch displayStatus {
        case "scheduled": .primary
        case "past": .secondary
        case "bot_joining", "processing": .orange
        case "recording": .red
        case "ready": .green
        case "failed": .red
        case "cancelled": .gray
        default: .secondary
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let cal = Calendar.current
        let now = Date()
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        if days > 0 {
            return days < 7 ? "In \(days)d" : "In \(days / 7)w"
        } else {
            let past = abs(days)
            if past < 7 { return "\(past)d ago" }
            if past < 30 { return "\(past / 7)w ago" }
            return "\(past / 30)mo ago"
        }
    }
}

private func syncedAgoText(_ date: Date) -> String {
    let diff = Date().timeIntervalSince(date)
    if diff < 60 { return "Synced just now" }
    if diff < 3600 { return "Synced \(Int(diff / 60))m ago" }
    if diff < 86400 { return "Synced \(Int(diff / 3600))h ago" }
    return "Synced \(date.formatted(.dateTime.month(.abbreviated).day()))"
}

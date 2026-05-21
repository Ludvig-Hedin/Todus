import SwiftUI

// MARK: - Meetings Hub (Split List + Detail)

struct MacMeetingsView: View {
    @Environment(MacAppServices.self) private var services

    @State private var selectedMeetingId: String? = nil
    @State private var searchText = ""
    @State private var statusFilter: String? = nil
    @State private var rotationAngle = 0.0

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

    var body: some View {
        HSplitView {
            meetingList
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 400)

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
        }
    }

    private var meetingList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Meetings")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.8))

                Spacer()

                Button {
                    Task { await services.meetingsService.syncFromCalendar() }
                } label: {
                    Image(systemName: services.meetingsService.isSyncing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(rotationAngle))
                }
                .buttonStyle(.plain)
                .help("Sync from Google Calendar")
                .disabled(services.meetingsService.isSyncing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

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

            if services.meetingsService.isLoading {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Spacer()
            } else if let errorMessage = services.meetingsService.loadError,
                      services.meetingsService.meetings.isEmpty {
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
                    Text("Sync your calendar to import meetings.")
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
    }

    private var groupedMeetings: [MeetingGroup] {
        let calendar = Calendar.current
        let today = Date()
        let todayStart = calendar.startOfDay(for: today)
        var todayItems: [MeetingItem] = []
        var thisWeekItems: [MeetingItem] = []
        var upcomingItems: [MeetingItem] = []
        var earlierItems: [MeetingItem] = []

        for meeting in services.meetingsService.meetings {
            let start = meeting.startsAt
            if calendar.isDate(start, inSameDayAs: today) {
                todayItems.append(meeting)
            } else if start >= todayStart {
                if calendar.isDate(start, equalTo: today, toGranularity: .weekOfYear) {
                    thisWeekItems.append(meeting)
                } else {
                    upcomingItems.append(meeting)
                }
            } else {
                earlierItems.append(meeting)
            }
        }

        var groups: [MeetingGroup] = []
        if !todayItems.isEmpty {
            groups.append(MeetingGroup(title: "Today", meetings: todayItems))
        }
        if !thisWeekItems.isEmpty {
            groups.append(MeetingGroup(title: "This Week", meetings: thisWeekItems))
        }
        if !upcomingItems.isEmpty {
            groups.append(MeetingGroup(title: "Upcoming", meetings: upcomingItems))
        }
        if !earlierItems.isEmpty {
            groups.append(MeetingGroup(title: "Earlier", meetings: earlierItems))
        }
        return groups
    }
}

private struct MeetingGroup: Identifiable {
    let title: String
    let meetings: [MeetingItem]
    var id: String { title }
}

private struct MacMeetingRowView: View {
    let meeting: MeetingItem
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(statusColor.opacity(0.8))
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(meeting.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text(timeLabel)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }

                    Text(statusLabel)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(statusColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onSelect()
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(meeting.title, forType: .string)
            } label: {
                Label("Copy title", systemImage: "doc.on.doc")
            }
            Button {
                let when = meeting.startsAt.formatted(date: .abbreviated, time: .shortened)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString("\(meeting.title) — \(when)", forType: .string)
            } label: {
                Label("Copy meeting summary", systemImage: "text.quote")
            }
        }
    }

    private var timeLabel: String {
        meeting.startsAt.formatted(date: .omitted, time: .shortened)
    }

    private var statusLabel: String {
        meeting.status.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var statusColor: Color {
        switch meeting.status {
        case "scheduled", "bot_joining", "recording":
            return .primary
        case "processing":
            return .orange
        case "ready":
            return .green
        case "failed", "cancelled":
            return .red
        default:
            return .secondary
        }
    }
}

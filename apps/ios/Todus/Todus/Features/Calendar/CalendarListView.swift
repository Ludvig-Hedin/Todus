import SwiftUI

/// Chronological list view — shows only days that have events.
/// Grouped by day with sticky headers showing date + week number.
/// Matches Apple Calendar iPhone list view style.
struct CalendarListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    @Binding var selectedDate: Date
    let events: [CalendarEvent]
    var onEventTap: ((CalendarEvent) -> Void)? = nil
    var onLoadMore: (() async -> Void)? = nil
    @State private var isLoadingMore = false
    @State private var eventAwaitingFolderPick: CalendarEvent?

    var body: some View {
        let groupedDays = groupedEventDays
        let cal = Calendar.current

        if groupedDays.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groupedDays) { dayGroup in
                            Section {
                                ForEach(dayGroup.events) { event in
                                    eventRow(event)
                                }
                            } header: {
                                dayHeader(dayGroup.date)
                            }
                            .id(dayGroup.date)
                        }

                        // Load more trigger
                        if onLoadMore != nil {
                            Color.clear
                                .frame(height: 1)
                                .task {
                                    guard !isLoadingMore else { return }
                                    isLoadingMore = true
                                    defer { isLoadingMore = false }
                                    await onLoadMore?()
                                }
                        }
                    }
                }
                .onChange(of: selectedDate) { _, newValue in
                    scrollListToDayIfPresent(proxy: proxy, cal: cal, groupedDays: groupedEventDays, day: newValue)
                }
                .onChange(of: events) { _, _ in
                    scrollListToDayIfPresent(proxy: proxy, cal: cal, groupedDays: groupedEventDays, day: selectedDate)
                }
                .sheet(item: $eventAwaitingFolderPick) { event in
                    FolderPickerSheet(title: "Add Event") { folder in
                        services.captureService.addItemToFolder(
                            kind: .event,
                            itemId: event.id,
                            title: event.title,
                            subtitle: event.startDate.formatted(date: .abbreviated, time: .shortened),
                            folder: folder,
                            in: modelContext
                        )
                        eventAwaitingFolderPick = nil
                    }
                    .appSheetBackground()
                }
            }
        }
    }

    private func scrollListToDayIfPresent(
        proxy: ScrollViewProxy,
        cal: Calendar,
        groupedDays: [EventDayGroup],
        day: Date
    ) {
        let target = cal.startOfDay(for: day)
        guard let matched = groupedDays.first(where: { cal.isDate($0.date, inSameDayAs: target) }) else {
            return
        }
        let scrollId = matched.date
        DispatchQueue.main.async {
            withAnimation(AppTheme.Motion.base) {
                proxy.scrollTo(scrollId, anchor: .top)
            }
        }
    }

    // MARK: - Day Header

    /// Sticky day header — "Friday – 3 Apr" + "W14" (week number)
    private func dayHeader(_ date: Date) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(date)
        let weekNumber = cal.component(.weekOfYear, from: date)

        return HStack {
            Text(date.formatted(.dateTime.weekday(.wide)))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isToday ? Color(red: 0.92, green: 0.23, blue: 0.21) : .primary)
            Text("– \(date.formatted(.dateTime.day().month(.abbreviated)))")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(isToday ? Color(red: 0.92, green: 0.23, blue: 0.21) : .primary)

            Spacer()

            Text("W\(weekNumber)")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppTheme.backgroundTop)
        .accessibilityElement(children: .combine)
        // VoiceOver reads the en-dash as "minus"; spell out the full date
        // plus the week number so it sounds natural.
        .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), week \(weekNumber)")
    }

    // MARK: - Event Row

    @ViewBuilder
    private func eventRow(_ event: CalendarEvent) -> some View {
        let eventColor = Color(
            red: event.calendarColorRed,
            green: event.calendarColorGreen,
            blue: event.calendarColorBlue
        )

        Button {
            AppHaptic.selection.play()
            onEventTap?(event)
        } label: {
            HStack(spacing: 10) {
                // Calendar color indicator
                Circle()
                    .fill(eventColor)
                    .frame(width: 8, height: 8)

                // Event title
                Text(event.title)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .accessibilityLabel(event.title)
                    .help(event.title)

                Spacer()

                // Time info
                Text(timeLabel(for: event))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                eventAwaitingFolderPick = event
            } label: {
                Label("Add to folder…", systemImage: "folder.badge.plus")
            }
            Button {
                UIPasteboard.general.string = event.title
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                Label("Copy title", systemImage: "doc.on.doc")
            }
            Button {
                let start = event.startDate.formatted(date: .abbreviated, time: .shortened)
                let end = event.endDate.formatted(date: .omitted, time: .shortened)
                UIPasteboard.general.string = "\(event.title) — \(start) – \(end)"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                Label("Copy event summary", systemImage: "text.quote")
            }
        }

        Divider()
            .padding(.leading, 34)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "calendar")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("No upcoming events")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)

            // Lightweight CTA — defers to the infra-owned CreateSheet via
            // AppServices.requestCreateSheet so the empty state is actionable
            // without us duplicating the create-event UI here.
            Button {
                services.requestCreateSheet = .event
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Create event")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint("Open the create event sheet")

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func timeLabel(for event: CalendarEvent) -> String {
        if event.isAllDay {
            return String(
                localized: "calendar.all-day",
                defaultValue: "all-day",
                comment: "Label for all-day calendar events"
            )
        }
        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    /// Groups events by day, sorted chronologically, skipping empty days.
    private var groupedEventDays: [EventDayGroup] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: events) { cal.startOfDay(for: $0.startDate) }
        return grouped
            .map { EventDayGroup(date: $0.key, events: $0.value.sorted { $0.startDate < $1.startDate }) }
            .sorted { $0.date < $1.date }
    }
}

/// A group of events for a single day.
struct EventDayGroup: Identifiable {
    let date: Date
    let events: [CalendarEvent]
    var id: Date { date }
}

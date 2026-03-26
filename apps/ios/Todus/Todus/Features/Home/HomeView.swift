import SwiftUI
import SwiftData
import EventKit

/// The Home / Today tab — a dashboard showing upcoming events, due tasks, and recent emails.
struct HomeView: View {
    @Environment(AppServices.self) private var services

    // Tasks due today — SwiftData live query
    @Query(filter: #Predicate<TaskRecord> { task in
        !task.completed
    }, sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]

    @State private var todaysEvents: [CalendarEvent] = []
    @State private var isLoadingEvents = false

    var body: some View {
        ZStack {
            AppTheme.backgroundTop.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    greetingSection
                    eventsSection
                    tasksSection
                    emailSection
                    Spacer(minLength: 80)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadTodaysEvents()
        }
    }

    // MARK: - Greeting

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.system(size: 28, weight: .bold))
            Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // MARK: - Events Section

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Today's Events", icon: "calendar", count: todaysEvents.count)

            if todaysEvents.isEmpty {
                emptyState(message: "No events today")
            } else {
                VStack(spacing: 8) {
                    ForEach(todaysEvents.prefix(5)) { event in
                        eventRow(event)
                    }
                }
            }
        }
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hue: Double(event.calendarColor % 360) / 360.0, saturation: 0.6, brightness: 0.8))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)

                if event.isAllDay {
                    Text("All day")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Text(event.startDate, format: .dateTime.hour().minute())
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(12)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Tasks Section

    private var tasksDueToday: [TaskRecord] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        return allTasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return dueDate >= today && dueDate < tomorrow
        }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Due Today", icon: "checklist", count: tasksDueToday.count)

            if tasksDueToday.isEmpty {
                emptyState(message: "No tasks due today")
            } else {
                VStack(spacing: 8) {
                    ForEach(tasksDueToday.prefix(5)) { task in
                        TaskRowView(
                            task: task,
                            onMoveRequested: {},
                            onOpenDetails: {}
                        )
                    }
                }
            }
        }
    }

    // MARK: - Email Section (placeholder)

    private var emailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Recent Emails", icon: "envelope.fill", count: 0)
            emptyState(message: "Connect email to see recent messages")
        }
    }

    // MARK: - Helpers

    private func sectionHeader(title: String, icon: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.surfaceSecondary, in: Capsule())
            }
            Spacer()
        }
    }

    private func emptyState(message: String) -> some View {
        Text(message)
            .font(.system(size: 14))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
    }

    private func loadTodaysEvents() async {
        isLoadingEvents = true
        let status = services.calendarService.authorizationStatus()
        if status == .fullAccess || status == .authorized {
            todaysEvents = await services.calendarService.todaysEvents()
                .sorted { $0.startDate < $1.startDate }
        }
        isLoadingEvents = false
    }
}

import SwiftUI
import SwiftData
import EventKit

/// The Home / Today tab — a dashboard showing upcoming events, due tasks, and recent emails.
struct HomeView: View {
    @Environment(AppServices.self) private var services

    // Tasks due today — SwiftData live query (excludes completed tasks)
    @Query(filter: #Predicate<TaskRecord> { task in
        !task.completed
    }, sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]

    @State private var todaysEvents: [CalendarEvent] = []
    @State private var isLoadingEvents = false

    // Cached tasks due today — recomputed only when allTasks changes.
    @State private var tasksDueToday: [TaskRecord] = []

    // Sheet state
    @State private var selectedTask: TaskRecord? = nil

    var body: some View {
        ZStack {
            AppTheme.backgroundTop.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header pinned outside the scroll for consistent position
                AppTopHeader(title: "Home")
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        greetingSection

                        if todaysEvents.isEmpty && tasksDueToday.isEmpty && !services.emailService.hasConnection {
                            self.getStartedSection
                        } else {
                            self.eventsSection
                            self.tasksSection
                            self.emailSection
                        }
                        Spacer(minLength: 80)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadTodaysEvents()
        }
        .onAppear { recomputeTasksDueToday() }
        .onChange(of: allTasks) { recomputeTasksDueToday() }
        // Task detail sheet — opened when a task row is tapped
        .sheet(item: $selectedTask) { task in
            TaskDetailSheet(task: task)
                .presentationDragIndicator(.visible)
                .presentationBackground(AppTheme.backgroundTop)
        }
    }

    // MARK: - Greeting

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        // 0–4 AM is still "night" from the user's perspective — not morning
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // MARK: - Events Section

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // "+" navigates to calendar tab where events are created natively
            sectionHeader(
                title: "Today's Events",
                icon: "calendar",
                count: todaysEvents.count,
                onAdd: { services.requestCreateSheet = .event }
            )

            if todaysEvents.isEmpty {
                emptyState(message: "No events today", onTap: { services.navigateTo = .calendar })
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
        // Tapping an event navigates to the calendar tab to view it in context
        Button {
            services.navigateTo = .calendar
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hue: Double(event.calendarColor % 360) / 360.0, saturation: 0.6, brightness: 0.8))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

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

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
            }
            .padding(12)
            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tasks Section

    private func recomputeTasksDueToday() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        tasksDueToday = allTasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return dueDate >= today && dueDate < tomorrow
        }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // "+" navigates to the tasks tab where the capture composer lives
            sectionHeader(
                title: "Due Today",
                icon: "checklist",
                count: tasksDueToday.count,
                onAdd: { services.requestCreateSheet = .task }
            )

            if tasksDueToday.isEmpty {
                emptyState(message: "No tasks due today", onTap: { services.navigateTo = .tasks })
            } else {
                VStack(spacing: 8) {
                    ForEach(tasksDueToday.prefix(5)) { task in
                        // Tapping opens the full task detail sheet
                        TaskRowView(
                            task: task,
                            onMoveRequested: {},
                            onOpenDetails: { selectedTask = task }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Email Section

    private var emailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Recent Emails",
                icon: "envelope.fill",
                count: services.emailService.threads.prefix(3).count,
                // "+" opens compose sheet if connected, otherwise navigates to email tab to connect
                onAdd: {
                    if services.emailService.hasConnection {
                        services.composeEmailSeedBody = nil
                        services.showsComposeEmail = true
                    } else {
                        services.navigateTo = .email
                    }
                }
            )

            if !services.emailService.hasConnection {
                // Not connected — prompt to connect
                emptyState(
                    message: "Connect Gmail to see your inbox",
                    onTap: { services.navigateTo = .email }
                )
            } else if services.emailService.threads.isEmpty {
                // Connected but no emails loaded yet
                emptyState(
                    message: "No recent emails",
                    onTap: { services.navigateTo = .email }
                )
            } else {
                // Show up to 3 recent threads from the already-loaded email service data
                VStack(spacing: 8) {
                    ForEach(Array(services.emailService.threads.prefix(3))) { thread in
                        Button {
                            services.navigateTo = .email
                        } label: {
                            HStack(spacing: 12) {
                                // Unread indicator dot
                                Circle()
                                    .fill(thread.unread ? Color.blue : Color.clear)
                                    .frame(width: 8, height: 8)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(thread.from.name)
                                            .font(.system(size: 14, weight: thread.unread ? .bold : .medium))
                                            .lineLimit(1)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text(thread.date, format: .dateTime.hour().minute())
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(thread.subject)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                        .foregroundStyle(.primary.opacity(0.8))
                                    Text(thread.snippet)
                                        .font(.system(size: 12))
                                        .lineLimit(1)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(AppTheme.cardBorder, lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Get Started (composite empty state)

    /// Shown when ALL sections are empty — replaces three separate empty states
    /// with a single onboarding card that guides the user to set up their services.
    private var getStartedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Get started")
                .font(.system(size: 18, weight: .bold))

            VStack(spacing: 10) {
                getStartedRow(
                    icon: "checkmark.circle",
                    title: "Create your first task",
                    subtitle: "Tap + or go to the Tasks tab",
                    action: { services.navigateTo = .tasks }
                )
                getStartedRow(
                    icon: "envelope.fill",
                    title: "Connect Gmail",
                    subtitle: "See your inbox right here",
                    action: { services.navigateTo = .email }
                )
                getStartedRow(
                    icon: "calendar",
                    title: "Check your calendar",
                    subtitle: "View today's events",
                    action: { services.navigateTo = .calendar }
                )
            }
        }
    }

    private func getStartedRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
            }
            .padding(14)
            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    /// Section header with icon, title, optional count badge, and a "+" action button.
    private func sectionHeader(
        title: String,
        icon: String,
        count: Int,
        onAdd: @escaping () -> Void
    ) -> some View {
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

            // Plus button — creates a new item in this category
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .minTouchTarget()
        }
    }

    /// Tappable empty state card — tapping triggers a navigation action.
    private func emptyState(message: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
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
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadTodaysEvents() async {
        isLoadingEvents = true
        if services.calendarService.canReadEvents() {
            todaysEvents = await services.calendarService.todaysEvents()
                .sorted { $0.startDate < $1.startDate }
        }
        isLoadingEvents = false
    }
}

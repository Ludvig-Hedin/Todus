import SwiftUI
import SwiftData
import EventKit

/// The Home / Today dashboard — desktop-optimized layout showing greeting,
/// today's events & tasks side by side, and recent emails below.
///
/// Aesthetic: "Refined Editorial" — monochrome, dense, soft corners, subtle contrast.
/// Think Craft / Linear / Things 3. No AI-dashboard vibe.
struct MacHomeView: View {
    @Environment(MacAppServices.self) private var services

    /// Called when the user taps a row to navigate to another section.
    var onNavigate: ((MacPrimarySelection) -> Void)? = nil

    // Tasks due today — SwiftData live query (excludes completed tasks)
    @Query(filter: #Predicate<TaskRecord> { task in
        !task.completed
    }, sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]

    @State private var todaysEvents: [CalendarEvent] = []
    @State private var isLoadingEvents = false
    @State private var tasksDueToday: [TaskRecord] = []
    @State private var isHoveringEventIndex: Int? = nil
    @State private var isHoveringTaskIndex: Int? = nil
    @State private var isHoveringEmailIndex: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Greeting header
            greetingHeader
                .padding(.bottom, MacTheme.spacing24)

            // When all sections are empty, show onboarding
            if todaysEvents.isEmpty && tasksDueToday.isEmpty && !services.emailService.hasConnection {
                getStartedSection
            } else {
                // Two-column: Events + Tasks side by side
                HStack(alignment: .top, spacing: MacTheme.spacing16) {
                    eventsColumn
                    tasksColumn
                }
                .padding(.bottom, MacTheme.spacing24)

                // Recent emails — full width
                emailsSection
            }
        }
        .task {
            await loadTodaysEvents()
            await services.emailService.checkConnection()
            if services.emailService.hasConnection && services.emailService.threads.isEmpty {
                await services.emailService.loadThreads(refresh: true)
            }
        }
        .onAppear { recomputeTasksDueToday() }
        .onChange(of: allTasks) { recomputeTasksDueToday() }
    }

    // MARK: - Greeting Header

    /// Time-based greeting with formatted date. Tight, editorial typography.
    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing4) {
            Text(greeting)
                .font(MacTheme.greetingFont())
                .foregroundStyle(MacTheme.textPrimary)
                .tracking(-0.3)

            Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(MacTheme.dateFont())
                .foregroundStyle(MacTheme.textSecondary)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // MARK: - Events Column

    private var eventsColumn: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing12) {
            sectionHeader(title: "TODAY'S EVENTS", count: todaysEvents.count)

            if todaysEvents.isEmpty {
                emptyCard(message: "No events today", icon: "calendar")
            } else {
                VStack(spacing: MacTheme.spacing4) {
                    ForEach(Array(todaysEvents.prefix(7).enumerated()), id: \.element.id) { index, event in
                        eventRow(event, index: index)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func eventRow(_ event: CalendarEvent, index: Int) -> some View {
        Button {
            // Navigate to the Calendar section
            onNavigate?(.calendar(.all))
        } label: {
            HStack(spacing: MacTheme.spacing8) {
                // Calendar color dot
                Circle()
                    .fill(Color(red: event.calendarColorRed, green: event.calendarColorGreen, blue: event.calendarColorBlue))
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(MacTheme.cardTitleFont())
                        .foregroundStyle(MacTheme.textPrimary)
                        .lineLimit(1)

                    if event.isAllDay {
                        Text("All day")
                            .font(MacTheme.cardSubtitleFont())
                            .foregroundStyle(MacTheme.textSecondary)
                    } else {
                        Text(event.startDate, format: .dateTime.hour().minute())
                            .font(MacTheme.cardSubtitleFont())
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, MacTheme.spacing12)
            .padding(.vertical, MacTheme.spacing8)
            .background(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .fill(isHoveringEventIndex == index ? MacTheme.surfaceHover : MacTheme.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointerStyle(.link)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHoveringEventIndex = hovering ? index : nil
            }
        }
    }

    // MARK: - Tasks Column

    private var tasksColumn: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing12) {
            sectionHeader(title: "DUE TODAY", count: tasksDueToday.count)

            if tasksDueToday.isEmpty {
                emptyCard(message: "No tasks due today", icon: "checkmark.circle")
            } else {
                VStack(spacing: MacTheme.spacing4) {
                    ForEach(Array(tasksDueToday.prefix(7).enumerated()), id: \.element.id) { index, task in
                        taskRow(task, index: index)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func taskRow(_ task: TaskRecord, index: Int) -> some View {
        Button {
            // Navigate to the Tasks section
            onNavigate?(.tasks)
        } label: {
            HStack(spacing: MacTheme.spacing8) {
                // Status icon
                Image(systemName: task.status.systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(task.status.tintColor)
                    .frame(width: 16)

                Text(task.title)
                    .font(MacTheme.cardTitleFont())
                    .foregroundStyle(MacTheme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                // Priority indicator
                if task.priority != .none {
                    priorityBadge(task.priority)
                }
            }
            .padding(.horizontal, MacTheme.spacing12)
            .padding(.vertical, MacTheme.spacing8)
            .background(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .fill(isHoveringTaskIndex == index ? MacTheme.surfaceHover : MacTheme.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointerStyle(.link)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHoveringTaskIndex = hovering ? index : nil
            }
        }
    }

    private func priorityBadge(_ priority: AppTaskPriority) -> some View {
        let (label, color): (String, Color) = switch priority {
        case .high: ("H", Color(red: 0.85, green: 0.3, blue: 0.3))
        case .medium: ("M", Color(red: 0.8, green: 0.65, blue: 0.2))
        case .low: ("L", MacTheme.textSecondary)
        case .none: ("", .clear)
        }

        return Text(label)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .frame(width: 16, height: 16)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: MacTheme.pillRadius, style: .continuous))
    }

    // MARK: - Emails Section

    private var emailsSection: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing12) {
            sectionHeader(title: "RECENT EMAILS", count: services.emailService.threads.prefix(5).count)

            if !services.emailService.hasConnection {
                // Show connect Gmail prompt with action button
                VStack(spacing: MacTheme.spacing8) {
                    emptyCard(message: "Connect Gmail to see your inbox", icon: "envelope")
                    Button {
                        Task { await services.emailService.connectGmail(authService: services.authService) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "link")
                                .font(.system(size: 11, weight: .medium))
                            Text("Connect Gmail")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, MacTheme.spacing16)
                        .padding(.vertical, MacTheme.spacing6)
                        .background(MacTheme.accent, in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .pointerStyle(.link)
                }
            } else if services.emailService.threads.isEmpty {
                if services.emailService.isLoadingThreads {
                    HStack(spacing: MacTheme.spacing8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading emails...")
                            .font(MacTheme.cardSubtitleFont())
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(MacTheme.spacing20)
                    .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
                } else {
                    emptyCard(message: "No recent emails", icon: "envelope.open")
                }
            } else {
                // Responsive grid of email cards
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 400), spacing: MacTheme.spacing8)], spacing: MacTheme.spacing8) {
                    ForEach(Array(services.emailService.threads.prefix(5).enumerated()), id: \.element.id) { index, thread in
                        emailCard(thread, index: index)
                    }
                }
            }
        }
    }

    private func emailCard(_ thread: EmailThread, index: Int) -> some View {
        Button {
            // Navigate to Email inbox
            onNavigate?(.email(.inbox))
        } label: {
            VStack(alignment: .leading, spacing: MacTheme.spacing4) {
                // Top row: sender + time
                HStack(spacing: MacTheme.spacing6) {
                    // Unread indicator
                    Circle()
                        .fill(thread.unread ? MacTheme.accent : Color.clear)
                        .frame(width: 6, height: 6)

                    Text(thread.from.name)
                        .font(.system(size: 13, weight: thread.unread ? .semibold : .medium))
                        .foregroundStyle(MacTheme.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(thread.date, format: .dateTime.hour().minute())
                        .font(MacTheme.metaFont())
                        .foregroundStyle(MacTheme.mutedText)
                }

                // Subject
                Text(thread.subject)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MacTheme.textPrimary.opacity(0.8))
                    .lineLimit(1)

                // Snippet
                Text(thread.snippet)
                    .font(MacTheme.cardSubtitleFont())
                    .foregroundStyle(MacTheme.textSecondary)
                    .lineLimit(2)
            }
            .padding(MacTheme.spacing12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .fill(isHoveringEmailIndex == index ? MacTheme.surfaceHover : MacTheme.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .stroke(thread.unread ? MacTheme.accent.opacity(0.2) : MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointerStyle(.link)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHoveringEmailIndex = hovering ? index : nil
            }
        }
    }

    // MARK: - Get Started (onboarding)

    private var getStartedSection: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing16) {
            Text("Get started")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MacTheme.textPrimary)

            // Horizontal layout for desktop — three action cards side by side
            HStack(spacing: MacTheme.spacing12) {
                getStartedCard(
                    icon: "checkmark.circle",
                    title: "Create your first task",
                    subtitle: "Organize your day",
                    action: { onNavigate?(.tasks) }
                )

                getStartedCard(
                    icon: "envelope",
                    title: "Connect Gmail",
                    subtitle: "See your inbox here",
                    action: { onNavigate?(.email(.inbox)) }
                )

                getStartedCard(
                    icon: "calendar",
                    title: "Check calendar",
                    subtitle: "View today's events",
                    action: { onNavigate?(.calendar(.all)) }
                )
            }
        }
    }

    private func getStartedCard(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: MacTheme.spacing8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(MacTheme.accent)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)

                Text(subtitle)
                    .font(MacTheme.cardSubtitleFont())
                    .foregroundStyle(MacTheme.textSecondary)
            }
            .padding(MacTheme.spacing16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(MacTheme.emptyStateSurface, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared Components

    /// Section header — all-caps label with count badge. Clean, editorial style.
    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(spacing: MacTheme.spacing6) {
            Text(title)
                .font(MacTheme.sectionHeaderFont())
                .foregroundStyle(MacTheme.mutedText)
                .tracking(0.8)

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(MacTheme.textSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(MacTheme.badgeSurface, in: RoundedRectangle(cornerRadius: MacTheme.pillRadius, style: .continuous))
            }

            Spacer()
        }
    }

    /// Empty state card — subtle, low-contrast
    private func emptyCard(message: String, icon: String) -> some View {
        HStack(spacing: MacTheme.spacing8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(MacTheme.mutedText.opacity(0.6))

            Text(message)
                .font(MacTheme.cardSubtitleFont())
                .foregroundStyle(MacTheme.mutedText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MacTheme.spacing16)
        .background(MacTheme.emptyStateSurface, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Data Loading

    private func recomputeTasksDueToday() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        tasksDueToday = allTasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return dueDate >= today && dueDate < tomorrow
        }
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

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
    @State private var hasComputedTasks = false
    @State private var isHoveringEventIndex: Int? = nil
    @State private var isHoveringTaskIndex: Int? = nil
    @State private var isHoveringEmailIndex: Int? = nil
    @State private var isLoadingAssistantBriefing = false
    @State private var selectedCalendarEvent: CalendarEvent? = nil
    @State private var selectedTask: TaskRecord? = nil
    @State private var selectedEmailThread: EmailThread? = nil

    private var isAssistantBriefingRefreshing: Bool {
        isLoadingAssistantBriefing && services.emailService.assistantBriefing != nil
    }

    private var isEventsRefreshing: Bool {
        isLoadingEvents && !todaysEvents.isEmpty
    }

    private var isEmailRefreshing: Bool {
        services.emailService.isLoadingThreads && !services.emailService.threads.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Greeting header
            greetingHeader
                .padding(.bottom, MacTheme.spacing24)

            if services.assistantAutomationPolicy.briefingEnabled
                && services.assistantAutomationPolicy.showHomeBriefing {
                assistantBriefingSection
                    .padding(.bottom, MacTheme.spacing20)
            }

            if showSetupBanner {
                setupBanner
                    .padding(.bottom, MacTheme.spacing20)
            }

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
            if services.assistantAutomationPolicy.briefingEnabled
                && services.assistantAutomationPolicy.showHomeBriefing {
                isLoadingAssistantBriefing = true
                _ = await services.emailService.loadAssistantBriefing()
                isLoadingAssistantBriefing = false
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

    private var needsEmailSetup: Bool {
        !services.emailService.hasConnection
    }

    private var needsCalendarSetup: Bool {
        !services.calendarService.canReadEvents()
    }

    private var showSetupBanner: Bool {
        !(todaysEvents.isEmpty && tasksDueToday.isEmpty && !services.emailService.hasConnection)
            && (needsEmailSetup || needsCalendarSetup)
    }

    private var setupBanner: some View {
        HStack(alignment: .top, spacing: MacTheme.spacing16) {
            VStack(alignment: .leading, spacing: MacTheme.spacing6) {
                Text("Finish setup")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)

                Text("Connect the remaining sources so Home can surface your full day.")
                    .font(MacTheme.cardSubtitleFont())
                    .foregroundStyle(MacTheme.textSecondary)
            }

            Spacer(minLength: MacTheme.spacing16)

            HStack(spacing: MacTheme.spacing8) {
                if needsCalendarSetup {
                    bannerButton(title: "Open Calendar") {
                        onNavigate?(.calendar(.all))
                    }
                }

                if needsEmailSetup {
                    bannerButton(title: "Connect Gmail") {
                        onNavigate?(.email(.inbox))
                    }
                }
            }
        }
        .padding(MacTheme.spacing16)
        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private var assistantBriefingSection: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing12) {
            sectionHeader(
                title: "ASSISTANT BRIEFING",
                count: services.emailService.assistantBriefing?.topPriorities.count ?? 0,
                isUpdating: isAssistantBriefingRefreshing
            )

            if isLoadingAssistantBriefing && services.emailService.assistantBriefing == nil {
                loadingCard(message: "Preparing your briefing")
            } else if let briefing = services.emailService.assistantBriefing {
                VStack(alignment: .leading, spacing: MacTheme.spacing12) {
                    assistantPriorityStrip(briefing)

                    HStack(alignment: .top, spacing: MacTheme.spacing12) {
                        assistantQueueColumn(
                            title: "Needs You",
                            items: briefing.needsYou.map { ($0.title, $0.summary) },
                            emptyMessage: "No reply or decision blockers right now."
                        )
                        assistantQueueColumn(
                            title: "Waiting On",
                            items: briefing.waitingOn.map { ($0.title, $0.summary) },
                            emptyMessage: "Nothing currently tracked as waiting on someone else."
                        )
                        assistantQueueColumn(
                            title: "Prepared",
                            items: briefing.prepared.map { ($0.title, $0.summary) },
                            emptyMessage: "No prepared drafts or actions waiting for approval."
                        )
                    }
                }
            }
        }
    }

    private func assistantPriorityStrip(_ briefing: AssistantBriefing) -> some View {
        HStack(spacing: MacTheme.spacing8) {
            if let urgentReply = briefing.today.urgentReply {
                assistantPriorityCard(title: "Urgent reply", detail: urgentReply.title)
            }
            if let topTask = briefing.today.topTask {
                assistantPriorityCard(title: "Top task", detail: topTask.title)
            }
            if let nextEvent = briefing.today.nextEvent {
                assistantPriorityCard(title: "Next event", detail: nextEvent.title)
            }
        }
    }

    private func assistantPriorityCard(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MacTheme.mutedText)
                .tracking(0.7)
            Text(detail)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(MacTheme.textPrimary)
                .lineLimit(2)
        }
        .padding(MacTheme.spacing12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func assistantQueueColumn(
        title: String,
        items: [(title: String, summary: String)],
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing8) {
            HStack(spacing: MacTheme.spacing6) {
                Text(title.uppercased())
                    .font(MacTheme.sectionHeaderFont())
                    .foregroundStyle(MacTheme.mutedText)
                    .tracking(0.8)
                Text("\(items.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(MacTheme.textSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(MacTheme.badgeSurface, in: RoundedRectangle(cornerRadius: MacTheme.pillRadius, style: .continuous))
                Spacer()
            }

            if items.isEmpty {
                emptyCard(message: emptyMessage, icon: "sparkles")
            } else {
                VStack(spacing: MacTheme.spacing6) {
                    ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(MacTheme.textPrimary)
                                .lineLimit(1)
                            Text(item.summary)
                                .font(MacTheme.cardSubtitleFont())
                                .foregroundStyle(MacTheme.textSecondary)
                                .lineLimit(2)
                        }
                        .padding(MacTheme.spacing12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Events Column

    private var eventsColumn: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing12) {
            sectionHeader(title: "TODAY'S EVENTS", count: todaysEvents.count, isUpdating: isEventsRefreshing)

            if isLoadingEvents && todaysEvents.isEmpty {
                loadingCard(message: "Loading today's events")
            } else if todaysEvents.isEmpty {
                emptyActionCard(
                    message: "No events today",
                    icon: "calendar",
                    actionTitle: "Open Calendar",
                    action: { onNavigate?(.calendar(.all)) }
                )
            } else {
                VStack(spacing: MacTheme.spacing4) {
                    ForEach(Array(todaysEvents.prefix(7).enumerated()), id: \.element.id) { index, event in
                        eventRow(event, index: index)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .popover(item: $selectedCalendarEvent, arrowEdge: .trailing) { event in
            eventDetailPopover(event)
        }
    }

    private func eventRow(_ event: CalendarEvent, index: Int) -> some View {
        Button {
            selectedCalendarEvent = event
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

            if !hasComputedTasks {
                loadingCard(message: "Loading today's tasks")
            } else if tasksDueToday.isEmpty {
                emptyActionCard(
                    message: "No tasks due today",
                    icon: "checkmark.circle",
                    actionTitle: "Open Tasks",
                    action: { onNavigate?(.tasks) }
                )
            } else {
                VStack(spacing: MacTheme.spacing4) {
                    ForEach(Array(tasksDueToday.prefix(7).enumerated()), id: \.element.id) { index, task in
                        taskRow(task, index: index)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .sheet(item: $selectedTask) { task in
            MacTaskDetailSheet(task: task)
                .frame(minWidth: 420, minHeight: 320)
        }
    }

    private func taskRow(_ task: TaskRecord, index: Int) -> some View {
        Button {
            selectedTask = task
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
            sectionHeader(
                title: "RECENT EMAILS",
                count: services.emailService.threads.prefix(5).count,
                isUpdating: isEmailRefreshing
            )

            if !services.emailService.hasConnection {
                // Connect Gmail prompt — button inside the empty state card
                VStack(spacing: MacTheme.spacing12) {
                    Image(systemName: "envelope")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(MacTheme.mutedText.opacity(0.6))

                    Text("Connect Gmail to see your inbox")
                        .font(MacTheme.cardSubtitleFont())
                        .foregroundStyle(MacTheme.mutedText)

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
                .frame(maxWidth: .infinity)
                .padding(.vertical, MacTheme.spacing20)
                .background(MacTheme.emptyStateSurface, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                        .stroke(MacTheme.cardBorder, lineWidth: 0.5)
                )
            } else if services.emailService.threads.isEmpty {
                if services.emailService.isLoadingThreads {
                    loadingCard(message: "Loading emails")
                } else {
                    emptyActionCard(
                        message: "No recent emails",
                        icon: "envelope.open",
                        actionTitle: "Open Inbox",
                        action: { onNavigate?(.email(.inbox)) }
                    )
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
        .sheet(item: $selectedEmailThread) { thread in
            MacEmailThreadView(threadId: thread.id)
                .frame(minWidth: 640, minHeight: 480)
        }
    }

    private func emailCard(_ thread: EmailThread, index: Int) -> some View {
        Button {
            selectedEmailThread = thread
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

    // MARK: - Event Detail Popover

    private func eventDetailPopover(_ event: CalendarEvent) -> some View {
        let color = Color(red: event.calendarColorRed, green: event.calendarColorGreen, blue: event.calendarColorBlue)

        return VStack(alignment: .leading, spacing: MacTheme.spacing8) {
            HStack(spacing: MacTheme.spacing8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 4, height: 20)
                Text(event.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
            }

            if event.isAllDay {
                Label("All day", systemImage: "clock")
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.textSecondary)
            } else {
                Label {
                    Text("\(event.startDate.formatted(date: .abbreviated, time: .shortened)) – \(event.endDate.formatted(date: .omitted, time: .shortened))")
                } icon: {
                    Image(systemName: "clock")
                }
                .font(.system(size: 12))
                .foregroundStyle(MacTheme.textSecondary)
            }

            Label(event.calendarName, systemImage: "calendar")
                .font(.system(size: 12))
                .foregroundStyle(MacTheme.textSecondary)
        }
        .padding(MacTheme.spacing16)
        .frame(minWidth: 220)
    }

    // MARK: - Shared Components

    /// Section header — all-caps label with count badge. Clean, editorial style.
    private func sectionHeader(title: String, count: Int, isUpdating: Bool = false) -> some View {
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

            if isUpdating {
                MacInlineRefreshBadge()
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

    private func emptyActionCard(
        message: String,
        icon: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: MacTheme.spacing8) {
            HStack(spacing: MacTheme.spacing8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(MacTheme.mutedText.opacity(0.6))

                Text(message)
                    .font(MacTheme.cardSubtitleFont())
                    .foregroundStyle(MacTheme.mutedText)
            }

            Button(actionTitle, action: action)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MacTheme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MacTheme.spacing16)
        .background(MacTheme.emptyStateSurface, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func loadingCard(message: String) -> some View {
        HStack(spacing: MacTheme.spacing8) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(MacTheme.cardSubtitleFont())
                .foregroundStyle(MacTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MacTheme.spacing20)
        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func bannerButton(title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(MacTheme.accent)
            .padding(.horizontal, MacTheme.spacing12)
            .padding(.vertical, MacTheme.spacing6)
            .background(MacTheme.badgeSurface, in: Capsule(style: .continuous))
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
        hasComputedTasks = true
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

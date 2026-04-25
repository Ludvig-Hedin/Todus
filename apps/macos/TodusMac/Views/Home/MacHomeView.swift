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

    /// Matches Settings → Focus Mode (hide AI nudges).
    @AppStorage("mac_focus_mode_enabled") private var macFocusModeEnabled = false

    /// Called when the user taps a row to navigate to another section.
    var onNavigate: ((MacPrimarySelection) -> Void)? = nil

    // Tasks due today — SwiftData live query (excludes completed tasks)
    @Query(filter: #Predicate<TaskRecord> { task in
        !task.completed
    }, sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]

    @State private var todaysEvents: [CalendarEvent] = []
    @State private var upcomingEvents: [CalendarEvent] = []
    @State private var isLoadingEvents = false
    @State private var isHoveringEventIndex: Int? = nil
    @State private var isHoveringUpcomingEventIndex: Int? = nil
    @State private var isHoveringTaskIndex: Int? = nil
    @State private var isHoveringEmailIndex: Int? = nil
    @State private var isHoveringMeetingIndex: Int? = nil
    @State private var isLoadingAssistantBriefing = false
    @State private var selectedCalendarEvent: CalendarEvent? = nil
    @State private var selectedUpcomingEvent: CalendarEvent? = nil
    @State private var selectedTask: TaskRecord? = nil
    @State private var selectedEmailThread: EmailThread? = nil
    @State private var selectedMeetingId: IdentifiableString? = nil
    @State private var proactiveNudgeThreadId: IdentifiableString? = nil
    @State private var isLoadingProactiveNudges = false

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
                .padding(.bottom, MacTheme.spacing16)

            if showProactiveAssistantOnHome {
                proactiveAssistantSection
                    .padding(.bottom, MacTheme.spacing20)
            }

            overviewStrip
                .padding(.bottom, MacTheme.spacing20)

            if services.assistantAutomationPolicy.briefingEnabled
                && services.assistantAutomationPolicy.showHomeBriefing {
                assistantBriefingSection
                    .padding(.bottom, MacTheme.spacing20)
            }

            if showSetupBanner {
                setupBanner
                    .padding(.bottom, MacTheme.spacing20)
            }

            // When nothing is set up and there is no local data, show onboarding
            if shouldShowGetStarted {
                getStartedSection
            } else {
                // Tasks first: action-oriented users scan obligations before the schedule.
                HStack(alignment: .top, spacing: MacTheme.spacing16) {
                    tasksColumn
                    eventsColumn
                    scheduleSidebar
                }
                .padding(.bottom, MacTheme.spacing24)

                docsAndToolsRow
                    .padding(.bottom, MacTheme.spacing24)

                emailsSection
            }
        }
        .sheet(item: $proactiveNudgeThreadId) { item in
            MacEmailThreadView(threadId: item.value)
                .frame(minWidth: 640, minHeight: 480)
        }
        .task {
            await loadCalendarData()
            await services.emailService.checkConnection()
            if services.emailService.hasConnection && services.emailService.threads.isEmpty {
                await services.emailService.loadThreads(refresh: true)
            }
            if services.authService.isAuthenticated {
                await services.meetingsService.loadMeetings()
            }
            if shouldRefreshProactiveNudges {
                isLoadingProactiveNudges = true
                await services.emailService.loadAssistantNudges()
                isLoadingProactiveNudges = false
            }
            if services.assistantAutomationPolicy.briefingEnabled
                && services.assistantAutomationPolicy.showHomeBriefing {
                isLoadingAssistantBriefing = true
                _ = await services.emailService.loadAssistantBriefing()
                isLoadingAssistantBriefing = false
            }
        }
    }

    // MARK: - Proactive AI suggestions (open loops)

    private var showProactiveAssistantOnHome: Bool {
        services.authService.isAuthenticated
            && services.emailService.hasConnection
            && services.assistantAutomationPolicy.assistantThreadActionsVisible
            && services.assistantAutomationPolicy.briefingEnabled
            && !macFocusModeEnabled
    }

    private var shouldRefreshProactiveNudges: Bool {
        services.authService.isAuthenticated
            && services.emailService.hasConnection
            && services.assistantAutomationPolicy.assistantThreadActionsVisible
            && services.assistantAutomationPolicy.briefingEnabled
            && !macFocusModeEnabled
    }

    private var proactiveNudgeCards: [MailAssistantNudge] {
        services.emailService.assistantNudges.filter { $0.count > 0 }
    }

    private var proactiveAssistantSection: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing12) {
            HStack(alignment: .top, spacing: MacTheme.spacing8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [MacTheme.accent, MacTheme.accent.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: MacTheme.spacing4) {
                    Text("Suggestions for you")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MacTheme.textPrimary)
                    Text("Picked up from your inbox — open a thread or jump to Mail.")
                        .font(MacTheme.metaFont())
                        .foregroundStyle(MacTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: MacTheme.spacing12)

                if isLoadingProactiveNudges {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                }

                Button("Open Mail") {
                    onNavigate?(.email(.inbox))
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MacTheme.accent)
                .pointerStyle(.link)
            }

            if isLoadingProactiveNudges && proactiveNudgeCards.isEmpty {
                loadingCard(message: "Checking your inbox for suggestions…")
            } else if !isLoadingProactiveNudges && proactiveNudgeCards.isEmpty {
                Text("Nothing to flag right now. When new replies or drafts need attention, they’ll show up here.")
                    .font(MacTheme.cardSubtitleFont())
                    .foregroundStyle(MacTheme.mutedText)
                    .padding(MacTheme.spacing12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MacTheme.emptyStateSurface, in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous)
                            .stroke(MacTheme.cardBorder.opacity(0.7), lineWidth: 0.5)
                    )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MacTheme.spacing8) {
                        ForEach(Array(proactiveNudgeCards.prefix(6))) { nudge in
                            proactiveNudgeCard(nudge)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(MacTheme.spacing16)
        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [MacTheme.accent.opacity(0.4), MacTheme.accent.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AI suggestions from your mail")
    }

    private func proactiveNudgeCard(_ nudge: MailAssistantNudge) -> some View {
        Button {
            if let id = nudge.threadIds.first {
                proactiveNudgeThreadId = IdentifiableString(value: id)
            } else {
                onNavigate?(.email(.inbox))
            }
        } label: {
            HStack(alignment: .top, spacing: MacTheme.spacing8) {
                Image(systemName: iconForAssistantNudge(nudge.type))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MacTheme.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: MacTheme.spacing6) {
                    HStack(alignment: .firstTextBaseline, spacing: MacTheme.spacing6) {
                        Text(nudge.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(MacTheme.textPrimary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        Text("\(nudge.count)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(MacTheme.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(MacTheme.badgeSurface, in: Capsule(style: .continuous))
                    }
                    Text(nudge.description)
                        .font(MacTheme.metaFont())
                        .foregroundStyle(MacTheme.textSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(MacTheme.spacing12)
            .frame(width: 272, alignment: .leading)
            .background(MacTheme.emptyStateSurface, in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .disabled(nudge.threadIds.isEmpty)
        .help("\(nudge.title): \(nudge.description)")
        .accessibilityLabel("\(nudge.title), \(nudge.count) threads")
    }

    private func iconForAssistantNudge(_ type: AssistantNudgeType) -> String {
        switch type {
        case .replyNeeded: return "arrowshape.turn.up.left.fill"
        case .meetingRequest: return "calendar.badge.clock"
        case .followUp: return "clock.arrow.circlepath"
        case .draftReady: return "doc.text.fill"
        }
    }

    // MARK: - Greeting Header

    /// Time-based greeting with formatted date. Tight, editorial typography.
    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing6) {
            Text(greeting)
                .font(MacTheme.greetingFont())
                .foregroundStyle(MacTheme.textPrimary)
                .tracking(-0.3)

            Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(MacTheme.dateFont())
                .foregroundStyle(MacTheme.textSecondary)

            Text(greetingSubtitle)
                .font(MacTheme.metaFont())
                .foregroundStyle(MacTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(greetingSubtitle)
        }
    }

    /// One-line context so Home feels guided, not like a blank dashboard.
    private var greetingSubtitle: String {
        if shouldShowGetStarted {
            return "Connect mail and calendar, or add a task, to populate this page."
        }
        let overdue = overdueTaskCount
        if overdue > 0 {
            return overdue == 1
                ? "You have 1 overdue task — it’s listed first below."
                : "You have \(overdue) overdue tasks — they’re listed first below."
        }
        if services.emailService.hasConnection, unreadEmailCount > 0 {
            return unreadEmailCount == 1
                ? "1 unread message in your inbox preview."
                : "\(unreadEmailCount) unread messages in your inbox preview."
        }
        if !todaysEvents.isEmpty {
            return "\(todaysEvents.count) event\(todaysEvents.count == 1 ? "" : "s") on your calendar today."
        }
        if incompleteTasks.isEmpty, todaysEvents.isEmpty {
            return "You’re clear on tasks and events for now."
        }
        return "A quick read on tasks, calendar, mail, and meetings."
    }

    private var overdueTaskCount: Int {
        let todayStart = Calendar.current.startOfDay(for: Date())
        return incompleteTasks.filter { task in
            guard let d = task.dueDate else { return false }
            return d < todayStart
        }.count
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
        !(todaysEvents.isEmpty && orderedPreviewTasks.isEmpty && !services.emailService.hasConnection)
            && (needsEmailSetup || needsCalendarSetup)
    }

    /// True when the user has no mail, no calendar access, and no open tasks.
    private var shouldShowGetStarted: Bool {
        !services.emailService.hasConnection
            && !services.calendarService.canReadEvents()
            && orderedPreviewTasks.isEmpty
    }

    private var incompleteTasks: [TaskRecord] {
        allTasks.filter { !$0.completed }
    }

    /// Open tasks sorted by urgency: overdue → today → future → no date.
    private var orderedPreviewTasks: [TaskRecord] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: todayStart)!
        func rank(_ t: TaskRecord) -> Int {
            guard let d = t.dueDate else { return 4 }
            if d < todayStart { return 0 }
            if d < tomorrow { return 1 }
            return 2
        }
        return incompleteTasks.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            switch (a.dueDate, b.dueDate) {
            case let (ad?, bd?): return ad < bd
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.createdAt > b.createdAt
            }
        }
    }

    private var unreadEmailCount: Int {
        services.emailService.threads.filter(\.unread).count
    }

    private var upcomingMeetings: [MeetingItem] {
        let now = Date()
        return services.meetingsService.meetings
            .filter { $0.startsAt >= now }
            .sorted { $0.startsAt < $1.startsAt }
    }

    private var assistantBriefingPriorityCount: Int {
        guard let briefing = services.emailService.assistantBriefing else { return 0 }
        return briefing.topPriorities.count
    }

    private var emailSectionSubtitle: String {
        if !services.emailService.hasConnection {
            return "Connect Gmail to load a short inbox preview on Home."
        }
        if services.emailService.threads.isEmpty {
            return "Threads from your inbox will show here after the first sync."
        }
        let total = services.emailService.threads.count
        let shown = min(5, total)
        if total <= shown {
            return "Latest threads from your inbox."
        }
        return "Showing the \(shown) most recent of \(total) loaded threads — use Open inbox for everything."
    }

    // MARK: - Overview strip

    private var overviewStrip: some View {
        let meetingCount = upcomingMeetings.count
        return VStack(alignment: .leading, spacing: MacTheme.spacing8) {
            Text("Jump to")
                .font(MacTheme.metaFont())
                .foregroundStyle(MacTheme.mutedText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MacTheme.spacing8) {
                    overviewChip(
                        title: "Tasks",
                        value: incompleteTasks.isEmpty ? "None open" : "\(incompleteTasks.count) open",
                        icon: "checkmark.circle",
                        help: "Open the Tasks tab",
                        action: { onNavigate?(.tasks) }
                    )
                    if services.emailService.hasConnection {
                        overviewChip(
                            title: "Mail",
                            value: unreadEmailCount == 0 ? "All caught up" : "\(unreadEmailCount) unread",
                            icon: "envelope.badge",
                            help: "Open Inbox",
                            action: { onNavigate?(.email(.inbox)) }
                        )
                    }
                    if services.calendarService.canReadEvents() {
                        overviewChip(
                            title: "Calendar",
                            value: todaysEvents.isEmpty ? "Free today" : "\(todaysEvents.count) today",
                            icon: "calendar",
                            help: "Open Calendar",
                            action: { onNavigate?(.calendar(.all)) }
                        )
                    }
                    if services.authService.isAuthenticated {
                        overviewChip(
                            title: "Meetings",
                            value: meetingCount == 0 ? "None upcoming" : "\(meetingCount) upcoming",
                            icon: "video",
                            help: "Open Meetings",
                            action: { onNavigate?(.meetings) }
                        )
                    }
                    overviewChip(
                        title: "Docs",
                        value: "Notes & docs",
                        icon: "doc.text",
                        help: "Open Docs in the app",
                        action: { onNavigate?(.docs) }
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func overviewChip(title: String, value: String, icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: MacTheme.spacing8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MacTheme.textPrimary)
                    Text(value)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(MacTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, MacTheme.spacing12)
            .padding(.vertical, MacTheme.spacing8)
            .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointerStyle(.link)
        .help(help)
        .accessibilityLabel("\(title). \(value)")
        .accessibilityHint(help)
    }

    private var setupBanner: some View {
        HStack(alignment: .top, spacing: MacTheme.spacing16) {
            VStack(alignment: .leading, spacing: MacTheme.spacing6) {
                Text("Finish setup")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)

                Text("Home works best with mail and calendar. Connect what’s missing — you can skip anything you don’t use.")
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
                title: "Assistant briefing",
                subtitle: "Summarized from your mail and tasks. Manage details in Mail or Tasks.",
                count: assistantBriefingPriorityCount > 0 ? assistantBriefingPriorityCount : nil,
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
                Text(title)
                    .font(MacTheme.sectionHeaderFont())
                    .foregroundStyle(MacTheme.textPrimary)
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
            sectionHeader(
                title: "Today",
                subtitle: "From calendars on this Mac",
                count: todaysEvents.isEmpty ? nil : todaysEvents.count,
                isUpdating: isEventsRefreshing,
                linkTitle: "Full calendar",
                linkAction: { onNavigate?(.calendar(.all)) }
            )

            if isLoadingEvents && todaysEvents.isEmpty {
                loadingCard(message: "Loading today’s events…")
            } else if todaysEvents.isEmpty {
                emptyActionCard(
                    message: "Nothing on the calendar for today",
                    icon: "calendar",
                    actionTitle: "Add in Calendar",
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
        .help("Show event details")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHoveringEventIndex = hovering ? index : nil
            }
        }
    }

    // MARK: - Tasks Column

    private var tasksColumn: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing12) {
            sectionHeader(
                title: "Tasks",
                subtitle: "Open items, overdue and due dates first",
                count: orderedPreviewTasks.isEmpty ? nil : orderedPreviewTasks.count,
                linkTitle: "All tasks",
                linkAction: { onNavigate?(.tasks) }
            )

            if orderedPreviewTasks.isEmpty {
                emptyActionCard(
                    message: "No open tasks — add one or sync from Reminders",
                    icon: "checkmark.circle",
                    actionTitle: "Go to Tasks",
                    action: { onNavigate?(.tasks) }
                )
            } else {
                VStack(spacing: MacTheme.spacing4) {
                    ForEach(Array(orderedPreviewTasks.prefix(8).enumerated()), id: \.element.id) { index, task in
                        taskRow(task, index: index, dueCaption: taskDueCaption(task))
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

    /// Right column: upcoming calendar (after today) + synced meetings + quick context.
    private var scheduleSidebar: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing16) {
            upcomingEventsSection
            meetingsSection
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .popover(item: $selectedUpcomingEvent, arrowEdge: .leading) { event in
            eventDetailPopover(event)
        }
        .sheet(item: $selectedMeetingId) { item in
            MacMeetingDetailView(meetingId: item.value)
                .frame(minWidth: 520, minHeight: 440)
        }
    }

    private var upcomingEventsSection: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing12) {
            sectionHeader(
                title: "Coming up",
                subtitle: "Tomorrow through the next two weeks",
                count: upcomingEvents.isEmpty ? nil : upcomingEvents.count,
                isUpdating: isEventsRefreshing,
                linkTitle: "Full calendar",
                linkAction: { onNavigate?(.calendar(.all)) }
            )

            if !services.calendarService.canReadEvents() {
                emptyActionCard(
                    message: "Allow Calendar access to see what’s next",
                    icon: "calendar.badge.exclamationmark",
                    actionTitle: "Open Calendar tab",
                    action: { onNavigate?(.calendar(.all)) }
                )
            } else if isLoadingEvents && upcomingEvents.isEmpty && todaysEvents.isEmpty {
                loadingCard(message: "Loading your schedule…")
            } else if upcomingEvents.isEmpty {
                emptyCard(message: "No more events in the next two weeks", icon: "calendar")
            } else {
                VStack(spacing: MacTheme.spacing4) {
                    ForEach(Array(upcomingEvents.prefix(6).enumerated()), id: \.element.id) { index, event in
                        upcomingEventRow(event, index: index)
                    }
                }
            }
        }
    }

    private var meetingsSection: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing12) {
            sectionHeader(
                title: "Meetings",
                subtitle: "Recorded in Todus (sync from Calendar in the Meetings tab)",
                count: upcomingMeetings.isEmpty ? nil : upcomingMeetings.count,
                isUpdating: services.meetingsService.isLoading && !services.meetingsService.meetings.isEmpty,
                linkTitle: "Meetings hub",
                linkAction: { onNavigate?(.meetings) }
            )

            if !services.authService.isAuthenticated {
                emptyCard(message: "Sign in to see meetings and recaps from your account", icon: "video")
            } else if services.meetingsService.isLoading && services.meetingsService.meetings.isEmpty {
                loadingCard(message: "Loading meetings…")
            } else if upcomingMeetings.isEmpty {
                emptyActionCard(
                    message: "No upcoming meetings synced yet",
                    icon: "video",
                    actionTitle: "Open Meetings",
                    action: { onNavigate?(.meetings) }
                )
            } else {
                VStack(spacing: MacTheme.spacing4) {
                    ForEach(Array(upcomingMeetings.prefix(5).enumerated()), id: \.element.id) { index, meeting in
                        meetingRow(meeting, index: index)
                    }
                }
            }
        }
    }

    private func upcomingEventRow(_ event: CalendarEvent, index: Int) -> some View {
        Button {
            selectedUpcomingEvent = event
        } label: {
            HStack(spacing: MacTheme.spacing8) {
                Circle()
                    .fill(Color(red: event.calendarColorRed, green: event.calendarColorGreen, blue: event.calendarColorBlue))
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(MacTheme.cardTitleFont())
                        .foregroundStyle(MacTheme.textPrimary)
                        .lineLimit(1)
                    Text(event.startDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(MacTheme.cardSubtitleFont())
                        .foregroundStyle(MacTheme.textSecondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, MacTheme.spacing12)
            .padding(.vertical, MacTheme.spacing8)
            .background(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .fill(isHoveringUpcomingEventIndex == index ? MacTheme.surfaceHover : MacTheme.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointerStyle(.link)
        .help("Show event details")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHoveringUpcomingEventIndex = hovering ? index : nil
            }
        }
    }

    private func meetingRow(_ meeting: MeetingItem, index: Int) -> some View {
        Button {
            selectedMeetingId = IdentifiableString(value: meeting.id)
        } label: {
            HStack(spacing: MacTheme.spacing8) {
                Image(systemName: "video.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(meeting.title)
                        .font(MacTheme.cardTitleFont())
                        .foregroundStyle(MacTheme.textPrimary)
                        .lineLimit(1)
                    Text(meeting.startsAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(MacTheme.cardSubtitleFont())
                        .foregroundStyle(MacTheme.textSecondary)
                }

                Spacer(minLength: 0)

                if !meeting.status.isEmpty {
                    Text(meeting.status.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(MacTheme.mutedText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(MacTheme.badgeSurface, in: RoundedRectangle(cornerRadius: MacTheme.pillRadius, style: .continuous))
                }
            }
            .padding(.horizontal, MacTheme.spacing12)
            .padding(.vertical, MacTheme.spacing8)
            .background(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .fill(isHoveringMeetingIndex == index ? MacTheme.surfaceHover : MacTheme.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointerStyle(.link)
        .help("Open meeting details")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHoveringMeetingIndex = hovering ? index : nil
            }
        }
    }

    private var docsAndToolsRow: some View {
        HStack(alignment: .center, spacing: MacTheme.spacing16) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(MacTheme.accent.opacity(0.9))
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: MacTheme.spacing4) {
                Text("Docs")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Text("Notes and documents live here — same place as the Docs sidebar item.")
                    .font(MacTheme.cardSubtitleFont())
                    .foregroundStyle(MacTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: MacTheme.spacing12)

            Button {
                onNavigate?(.docs)
            } label: {
                Text("Open Docs")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, MacTheme.spacing16)
                    .padding(.vertical, MacTheme.spacing8)
                    .background(MacTheme.accent, in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .pointerStyle(.link)
            .help("Switch to the Docs tab")
            .accessibilityLabel("Open Docs tab")
        }
        .padding(MacTheme.spacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func taskDueCaption(_ task: TaskRecord) -> String? {
        guard let due = task.dueDate else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        if due < today { return "Overdue" }
        if cal.isDateInToday(due) { return "Today" }
        if cal.isDateInTomorrow(due) { return "Tomorrow" }
        return due.formatted(date: .abbreviated, time: .omitted)
    }

    private func taskRow(_ task: TaskRecord, index: Int, dueCaption: String?) -> some View {
        Button {
            selectedTask = task
        } label: {
            HStack(spacing: MacTheme.spacing8) {
                // Status icon
                Image(systemName: task.status.systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(task.status.tintColor)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(MacTheme.cardTitleFont())
                        .foregroundStyle(MacTheme.textPrimary)
                        .lineLimit(1)
                    if let dueCaption {
                        Text(dueCaption)
                            .font(MacTheme.cardSubtitleFont())
                            .foregroundStyle(dueCaption == "Overdue" ? MacTheme.calendarNowIndicator : MacTheme.textSecondary)
                    }
                }

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
        .help("Edit task")
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
                title: "Mail",
                subtitle: emailSectionSubtitle,
                count: services.emailService.hasConnection && !services.emailService.threads.isEmpty
                    ? services.emailService.threads.count : nil,
                isUpdating: isEmailRefreshing,
                linkTitle: services.emailService.hasConnection ? "Open inbox" : nil,
                linkAction: services.emailService.hasConnection ? { onNavigate?(.email(.inbox)) } : nil
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
        .help("Open thread: \(thread.subject)")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHoveringEmailIndex = hovering ? index : nil
            }
        }
    }

    // MARK: - Get Started (onboarding)

    private var getStartedSection: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing16) {
            VStack(alignment: .leading, spacing: MacTheme.spacing6) {
                Text("Get started")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Text("Choose any step below. You can add the others whenever you’re ready.")
                    .font(MacTheme.metaFont())
                    .foregroundStyle(MacTheme.mutedText)
            }

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

    /// Section title with optional subtitle, count badge, refresh indicator, and trailing navigation link.
    private func sectionHeader(
        title: String,
        subtitle: String? = nil,
        count: Int? = nil,
        isUpdating: Bool = false,
        linkTitle: String? = nil,
        linkAction: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing6) {
            HStack(alignment: .firstTextBaseline, spacing: MacTheme.spacing8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)

                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(MacTheme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(MacTheme.badgeSurface, in: RoundedRectangle(cornerRadius: MacTheme.pillRadius, style: .continuous))
                }

                if isUpdating {
                    MacInlineRefreshBadge()
                }

                Spacer(minLength: MacTheme.spacing8)

                if let linkTitle, let linkAction {
                    Button(linkTitle, action: linkAction)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MacTheme.accent)
                        .pointerStyle(.link)
                }
            }

            if let subtitle {
                Text(subtitle)
                    .font(MacTheme.metaFont())
                    .foregroundStyle(MacTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    /// Loads today's events plus future events (tomorrow through 14 days) for the sidebar.
    private func loadCalendarData() async {
        isLoadingEvents = true
        defer { isLoadingEvents = false }
        guard services.calendarService.canReadEvents() else {
            todaysEvents = []
            upcomingEvents = []
            return
        }
        let todayList = await services.calendarService.todaysEvents()
            .sorted { $0.startDate < $1.startDate }
        let cal = Calendar.current
        let tomorrowStart = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        let horizonEnd = cal.date(byAdding: .day, value: 15, to: cal.startOfDay(for: Date()))!
        let future = await services.calendarService.events(from: tomorrowStart, to: horizonEnd)
            .sorted { $0.startDate < $1.startDate }
        todaysEvents = todayList
        upcomingEvents = future
    }
}

import SwiftUI
import SwiftData
import EventKit
import UIKit

/// The Home / Today tab — a dashboard showing upcoming events, due tasks, and recent emails.
struct HomeView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FolderRecord.createdAt) private var folders: [FolderRecord]

    // Tasks due today — SwiftData live query (excludes completed tasks)
    @Query(filter: #Predicate<TaskRecord> { task in
        !task.completed
    }, sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]

    @State private var todaysEvents: [CalendarEvent] = []
    @State private var isLoadingEvents = false
    @State private var hasLoadedEmailState = false
    @State private var isLoadingAssistantBriefing = false

    // Cached tasks due today — recomputed only when allTasks changes.
    @State private var tasksDueToday: [TaskRecord] = []

    // Sheet state
    @State private var selectedTask: TaskRecord? = nil
    @State private var selectedCalendarEvent: CalendarEvent? = nil
    @State private var selectedEmailThread: EmailThread? = nil
    @State private var proactiveSuggestionThread: HomeProactiveThreadRoute? = nil
    @State private var isLoadingProactiveNudges = false
    @State private var showDocsSheet = false

    /// Most recent foreground refresh — used to gate the scenePhase listener so we don't
    /// double-refresh when the app comes back to foreground rapidly (e.g. after dismissing
    /// a system permission prompt or share sheet).
    @State private var lastRefresh: Date = .distantPast
    private let foregroundRefreshThrottle: TimeInterval = 5

    var body: some View {
        ZStack {
            AppTheme.backgroundTop.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header pinned outside the scroll for consistent position
                AppTopHeader(title: "Home")
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 24) {
                        greetingSection

                        if showProactiveAssistantOnHome {
                            proactiveAssistantSection
                        }

                        if services.assistantAutomationPolicy.briefingEnabled
                            && services.assistantAutomationPolicy.showHomeBriefing {
                            assistantBriefingSection
                        }

                        if todaysEvents.isEmpty && tasksDueToday.isEmpty && !services.emailService.hasConnection {
                            getStartedSection
                        } else {
                            if showSetupCard {
                                setupCard
                            }

                            eventsSection
                            tasksSection
                            emailSection
                        }

                        // Pages not pinned to the tab bar — only shown in developer mode
                        if services.developerModeEnabled {
                            moreSection
                        }
                        Spacer(minLength: 130)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .clipped()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadHomeData()
            lastRefresh = Date()
        }
        .onAppear { recomputeTasksDueToday() }
        .onChange(of: allTasks) { recomputeTasksDueToday() }
        // Refresh on foreground so events/inbox/assistant data don't go stale while the
        // app is backgrounded. Throttled to skip if the last refresh was within 5s — this
        // avoids a double-fetch when scenePhase fires .active immediately after our `.task`
        // (or after dismissing a system permission prompt that briefly suspends the scene).
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            guard Date().timeIntervalSince(lastRefresh) >= foregroundRefreshThrottle else { return }
            Task {
                // Pull in any reminders the user added/edited in Apple Reminders while we
                // were backgrounded — keeps the SwiftData task store aligned with system state.
                await services.remindersSyncService.refreshFromReminders(in: modelContext)
                await loadHomeData()
                lastRefresh = Date()
            }
        }
        // Task detail sheet — opened when a task row is tapped
        .sheet(item: $selectedTask) { task in
            TaskDetailSheet(task: task)
                .presentationDragIndicator(Visibility.visible)
                .appSheetBackground()
        }
        .sheet(isPresented: $showDocsSheet) {
            NavigationStack {
                DocsBrowserView()
                    .navigationTitle("Docs")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showDocsSheet = false }
                        }
                    }
            }
            .presentationDragIndicator(Visibility.visible)
            .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        .sheet(item: $selectedCalendarEvent) { event in
            EKEventDetailSheet(eventId: event.id)
                .presentationDragIndicator(Visibility.visible)
        }
        .sheet(item: $selectedEmailThread) { thread in
            NavigationStack {
                EmailThreadView(threadId: thread.id)
            }
            .presentationDragIndicator(Visibility.visible)
            .appSheetBackground()
        }
        .sheet(item: $proactiveSuggestionThread) { route in
            NavigationStack {
                EmailThreadView(threadId: route.id)
            }
            .presentationDragIndicator(Visibility.visible)
            .appSheetBackground()
        }
    }

    /// Sheet route for opening a thread from AI suggestion cards.
    private struct HomeProactiveThreadRoute: Identifiable {
        let id: String
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

    private var needsEmailSetup: Bool {
        hasLoadedEmailState && !services.emailService.hasConnection
    }

    private var needsCalendarSetup: Bool {
        !services.calendarService.canReadEvents()
    }

    private var showSetupCard: Bool {
        !(todaysEvents.isEmpty && tasksDueToday.isEmpty && !services.emailService.hasConnection)
            && (needsEmailSetup || needsCalendarSetup)
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Finish setup")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Connect the remaining sources so Home can show your full day at a glance.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                if needsEmailSetup {
                    setupRow(
                        icon: "envelope.fill",
                        title: "Connect Gmail",
                        subtitle: "Bring your inbox into Home and Email",
                        actionTitle: "Open Email",
                        action: { services.navigateTo = .email }
                    )
                }

                if needsCalendarSetup {
                    setupRow(
                        icon: "calendar",
                        title: "Enable Calendar Access",
                        subtitle: "Show today's events alongside your tasks",
                        actionTitle: "Open Calendar",
                        action: { services.navigateTo = .calendar }
                    )
                }
            }
        }
        .padding(16)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
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

    private var isAssistantBriefingRefreshing: Bool {
        isLoadingAssistantBriefing && services.emailService.assistantBriefing != nil
    }

    private var isEventsRefreshing: Bool {
        isLoadingEvents && !todaysEvents.isEmpty
    }

    private var isEmailRefreshing: Bool {
        services.emailService.isLoadingThreads && !services.emailService.threads.isEmpty
    }

    private var showProactiveAssistantOnHome: Bool {
        services.authService.isAuthenticated
            && services.emailService.hasConnection
            && services.assistantAutomationPolicy.assistantThreadActionsVisible
            && services.assistantAutomationPolicy.briefingEnabled
    }

    private var proactiveNudgeCards: [MailAssistantNudge] {
        services.emailService.assistantNudges.filter { $0.count > 0 }
    }

    private var proactiveAssistantSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0, green: 0xAA / 255, blue: 0xF5 / 255),
                                Color(red: 0xEF / 255, green: 0, blue: 0xC2 / 255),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Suggestions for you")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("From your inbox — tap a card to open the thread.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                if isLoadingProactiveNudges {
                    ProgressView()
                        .padding(.trailing, 4)
                }

                Button("Mail") {
                    services.navigateTo = .email
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            }

            if isLoadingProactiveNudges && proactiveNudgeCards.isEmpty {
                loadingState(message: "Checking your inbox…")
            } else if !isLoadingProactiveNudges && proactiveNudgeCards.isEmpty {
                Text("You’re caught up on what we’re tracking. New replies and drafts will surface here.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.mutedText)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(proactiveNudgeCards.prefix(6))) { nudge in
                            proactiveNudgeCard(nudge)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.45), Color.accentColor.opacity(0.08)],
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
                proactiveSuggestionThread = HomeProactiveThreadRoute(id: id)
            } else {
                services.navigateTo = .email
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconForAssistantNudge(nudge.type))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(nudge.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        Text("\(nudge.count)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.surfaceSecondary, in: Capsule())
                    }
                    Text(nudge.description)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(width: 268, alignment: .leading)
            .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(nudge.threadIds.isEmpty)
    }

    private func iconForAssistantNudge(_ type: AssistantNudgeType) -> String {
        switch type {
        case .replyNeeded: return "arrowshape.turn.up.left.fill"
        case .meetingRequest: return "calendar.badge.clock"
        case .followUp: return "clock.arrow.circlepath"
        case .draftReady: return "doc.text.fill"
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
                actionTitle: "Open",
                isUpdating: isEventsRefreshing,
                onOpen: { services.navigateTo = .calendar },
                onAdd: { services.requestCreateSheet = .event }
            )

            if isLoadingEvents && todaysEvents.isEmpty {
                loadingState(message: "Loading today's events")
            } else if todaysEvents.isEmpty {
                // If we don't have calendar permission, the empty state can't tell the
                // difference between "no events" and "we literally can't see your events".
                // Surface that distinction so the user can act, instead of staring at a
                // perpetually empty card.
                if !services.calendarService.canReadEvents() {
                    permissionEmptyState(
                        message: "Enable calendar access in Settings to see today's events",
                        actionTitle: "Open Settings"
                    )
                } else {
                    emptyState(message: "No events today", onTap: { services.navigateTo = .calendar })
                }
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
        Button {
            selectedCalendarEvent = event
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hue: Double(event.calendarColor % 360) / 360.0, saturation: 0.6, brightness: 0.8))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 14, weight: .medium))
                        // Allow two lines so longer event titles ("Q3 OKR review with the
                        // platform team") aren't visually cut off mid-word in the home feed.
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)

                    if let folderName = folderName(for: event.folderID) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 11, weight: .medium))
                            Text(folderName)
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(.secondary)
                    }

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
            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Unfiled") {
                moveEvent(event, to: nil)
            }
            if !folders.isEmpty {
                Divider()
            }
            ForEach(folders) { folder in
                Button(folder.name) {
                    moveEvent(event, to: folder.id)
                }
            }
        }
    }

    private var assistantBriefingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
                Text("Assistant Briefing")
                    .font(.system(size: 15, weight: .semibold))
                if isAssistantBriefingRefreshing {
                    InlineRefreshBadge()
                }
            }

            if isLoadingAssistantBriefing && services.emailService.assistantBriefing == nil {
                loadingState(message: "Preparing your briefing")
            } else if let briefing = services.emailService.assistantBriefing {
                VStack(spacing: 10) {
                    assistantPriorityStrip(briefing)
                    assistantQueueSection(
                        title: "Needs You",
                        items: briefing.needsYou.map { ($0.title, $0.summary, $0.threadId) },
                        emptyMessage: "No reply or decision blockers right now."
                    )
                    assistantQueueSection(
                        title: "Waiting On",
                        items: briefing.waitingOn.map { ($0.title, $0.summary, $0.threadId) },
                        emptyMessage: "Nothing currently tracked as waiting on someone else."
                    )
                    assistantQueueSection(
                        title: "Prepared",
                        items: briefing.prepared.map { ($0.title, $0.summary, $0.threadId) },
                        emptyMessage: "No prepared drafts or actions waiting for approval."
                    )
                }
            }
        }
    }

    private func assistantPriorityStrip(_ briefing: AssistantBriefing) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let urgentReply = briefing.today.urgentReply {
                    assistantMiniCard(
                        title: "Urgent reply",
                        detail: urgentReply.title,
                        action: { services.navigateTo = .email }
                    )
                }
                if let topTask = briefing.today.topTask {
                    assistantMiniCard(
                        title: "Top task",
                        detail: topTask.title,
                        action: { services.navigateTo = .tasks }
                    )
                }
                if let nextEvent = briefing.today.nextEvent {
                    assistantMiniCard(
                        title: "Next event",
                        detail: nextEvent.title,
                        action: { services.navigateTo = .calendar }
                    )
                }
            }
            .padding(.horizontal, 1)
        }
        .frame(maxWidth: .infinity)
    }

    private func assistantMiniCard(title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
                    .textCase(.uppercase)
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(width: 180, alignment: .leading)
            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func assistantQueueSection(
        title: String,
        items: [(title: String, summary: String, threadId: String?)],
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
                    .textCase(.uppercase)
                Spacer()
                Text("\(items.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AppTheme.surfaceSecondary, in: Capsule())
            }

            if items.isEmpty {
                emptyState(message: emptyMessage, onTap: {})
                    .allowsHitTesting(false)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, item in
                        Button {
                            services.navigateTo = .email
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(item.summary)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                                    .stroke(AppTheme.cardBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Tasks Section

    private func recomputeTasksDueToday() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return }
        tasksDueToday = allTasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return dueDate >= today && dueDate < tomorrow
        }
    }

    private func folderName(for folderID: UUID?) -> String? {
        guard let folderID else { return nil }
        return folders.first(where: { $0.id == folderID })?.name
    }

    private func moveEvent(_ event: CalendarEvent, to folderID: UUID?) {
        Task {
            await services.calendarService.setFolderID(folderID, for: event.id)
            await loadTodaysEvents()
        }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // "+" navigates to the tasks tab where the capture composer lives
            sectionHeader(
                title: "Due Today",
                icon: "checklist",
                count: tasksDueToday.count,
                actionTitle: "View all",
                isUpdating: false,
                onOpen: { services.navigateTo = .tasks },
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
                actionTitle: "Open",
                isUpdating: isEmailRefreshing,
                onOpen: { services.navigateTo = .email },
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

            if !hasLoadedEmailState {
                loadingState(message: "Checking your inbox")
            } else if !services.emailService.hasConnection {
                // Not connected — prompt to connect
                emptyState(
                    message: "Connect Gmail to see your inbox",
                    onTap: { services.navigateTo = .email }
                )
            } else if services.emailService.isLoadingThreads && services.emailService.threads.isEmpty {
                loadingState(message: "Loading recent emails")
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
                            selectedEmailThread = thread
                        } label: {
                            HStack(spacing: 12) {
                                // Unread indicator dot
                                Circle()
                                    .fill(thread.unread ? Color.primary : Color.clear)
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
                            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
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

    // MARK: - More Section (pages not in the tab bar)

    /// Shows AppTab pages not pinned to the nav bar, plus the always-available Docs page.
    /// Keeps the tab bar lean while ensuring every part of the app is reachable from Home.
    @ViewBuilder
    private var moreSection: some View {
        let extraTabs = AppTab.allCases.filter { !services.tabBarTabs.contains($0) && $0 != .home && $0 != .create && $0 != .ai }
        // Always show this section — Docs is always here even when all tabs are in the bar
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("More pages")
                        .font(.system(size: 15, weight: .semibold))
                }

                Text("Features not pinned to your tab bar")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                // Dynamic tab-based cards
                ForEach(extraTabs) { tab in
                    moreCard(for: tab)
                }

                // Docs — always present regardless of tab bar configuration
                docsCard
            }
        }
    }

    private func moreCard(for tab: AppTab) -> some View {
        Button {
            if tab == .calendar {
                // Calendar uses UIKit — navigate to the tab directly
                services.navigateTo = .calendar
            } else {
                services.navigateToSheet = tab
            }
        } label: {
            moreCardContent(
                icon: tab.activeIcon,
                title: tab.title,
                subtitle: tab.description,
                isSecondary: true
            )
        }
        .buttonStyle(.plain)
    }

    /// Docs is not an AppTab (it's a web view), so it always lives here.
    private var docsCard: some View {
        Button { showDocsSheet = true } label: {
            moreCardContent(
                icon: "doc.text",
                title: "Docs",
                subtitle: "Notes and documents",
                isSecondary: true
            )
        }
        .buttonStyle(.plain)
    }

    private func moreCardContent(
        icon: String,
        title: String,
        subtitle: String,
        isSecondary: Bool = false
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isSecondary ? AppTheme.mutedText : .primary)
                .frame(width: 36, height: 36)
                .background(
                    isSecondary ? AppTheme.surfaceSecondary : Color.primary.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSecondary ? Color.primary.opacity(0.82) : Color.primary)
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
        .background(
            isSecondary ? AppTheme.surfaceSecondary : AppTheme.surfacePrimary,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
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
                    .foregroundStyle(.primary)
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
            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
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
        actionTitle: String,
        isUpdating: Bool = false,
        onOpen: @escaping () -> Void,
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
            if isUpdating {
                InlineRefreshBadge()
            }
            Spacer()

            Button(actionTitle, action: onOpen)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.accent)

            // Plus button — creates a new item in this category
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.inline, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.inline, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .minTouchTarget()
        }
    }

    /// Empty state for missing system permission (e.g. calendar/reminders access denied).
    /// Tapping deep-links into Settings so the user can grant access without hunting for it.
    private func permissionEmptyState(message: String, actionTitle: String) -> some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            VStack(spacing: 8) {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(actionTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Tappable empty state card — tapping triggers a navigation action.
    private func emptyState(message: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadingState(message: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(14)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }

    private func setupRow(
        icon: String,
        title: String,
        subtitle: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28, height: 28)
                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.inline, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(actionTitle, action: action)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
        }
    }

    private func loadTodaysEvents() async {
        let trace = PerformanceTrace.beginInterval(
            PerformanceTrace.loadTodayEvents,
            message: "HomeView.loadTodaysEvents begin"
        )
        isLoadingEvents = true
        defer {
            isLoadingEvents = false
            PerformanceTrace.endInterval(
                PerformanceTrace.loadTodayEvents,
                trace,
                message: "HomeView.loadTodaysEvents end count=\(todaysEvents.count)"
            )
        }
        if services.calendarService.canReadEvents() {
            todaysEvents = await services.calendarService.todaysEvents()
                .sorted { $0.startDate < $1.startDate }
        }
    }

    private func loadHomeData() async {
        await services.emailService.checkConnection()
        hasLoadedEmailState = true

        if services.emailService.hasConnection {
            await services.emailService.ensureInitialInboxLoaded()
        }

        await loadTodaysEvents()

        if services.authService.isAuthenticated,
           services.emailService.hasConnection,
           services.assistantAutomationPolicy.assistantThreadActionsVisible,
           services.assistantAutomationPolicy.briefingEnabled {
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


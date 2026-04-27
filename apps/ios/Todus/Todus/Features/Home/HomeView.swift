import SwiftUI
import SwiftData
import EventKit
import UIKit

/// The Home / Today tab — a dashboard showing upcoming events, due tasks, and recent emails.
struct HomeView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query(
        sort: [
            SortDescriptor(\FolderRecord.position, order: .forward),
            SortDescriptor(\FolderRecord.createdAt, order: .forward),
        ]
    )
    private var folders: [FolderRecord]

    // Tasks due today — SwiftData live query (excludes completed tasks)
    @Query(filter: #Predicate<TaskRecord> { task in
        !task.completed
    }, sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]

    // Unfiltered count — used to drive the "Create your first task" setup prompt so
    // a user who has only completed tasks isn't told they haven't created any yet.
    @Query private var allTasksIncludingCompleted: [TaskRecord]

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
    /// Sheet for opening a thread by id — used by hero priority callout and briefing rows
    /// where we don't have the full EmailThread payload, only the id.
    @State private var briefingThreadRoute: HomeThreadIdRoute? = nil
    @State private var showDocsSheet = false

    /// Most recent foreground refresh — used to gate the scenePhase listener so we don't
    /// double-refresh when the app comes back to foreground rapidly (e.g. after dismissing
    /// a system permission prompt or share sheet).
    @State private var lastRefresh: Date = .distantPast
    @State private var selectedFolder: FolderRecord? = nil
    @State private var showFolderEditSheet: Bool = false
    private let foregroundRefreshThrottle: TimeInterval = 5

    @State private var headerHeight: CGFloat = 60
    private let scrimTail: CGFloat = 32

    var body: some View {
        ZStack(alignment: .top) {
            AppTheme.backgroundTop.ignoresSafeArea()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    briefingHero

                    if showSetupChecklist {
                        setupChecklist
                    }

                    if showBriefingFeed {
                        briefingFeedSection
                    }

                    eventsSection
                    tasksSection
                    emailSection

                    foldersSection

                    // Pages not pinned to the tab bar — only shown in developer mode
                    if services.effectiveDeveloperModeEnabled {
                        moreSection
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.bottom, 32, for: .scrollContent)
            .safeAreaInset(edge: .top) {
                Color.clear.frame(height: headerHeight + scrimTail)
            }

            // Floating header — content scrolls under it; scrim gradient fades below.
            VStack(spacing: 0) {
                AppTopHeader(title: "Home")
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 4)
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                headerHeight = height
            }
            .pageHeaderScrim(scrimHeight: headerHeight + scrimTail)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            // EmailService restores `hasConnection` from UserDefaults in init. If it's
            // already resolved (true on prior launch), trust that for the first paint
            // so the email section doesn't briefly show "Checking your inbox" before
            // the async checkConnection() call lands.
            if services.emailService.hasResolvedConnection {
                hasLoadedEmailState = true
            }
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
            .appSheetBackground()
            .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        .sheet(item: $selectedCalendarEvent) { event in
            EKEventDetailSheet(eventId: event.id)
                .presentationDragIndicator(Visibility.visible)
                .appSheetBackground()
        }
        .sheet(item: $selectedEmailThread) { thread in
            NavigationStack {
                EmailThreadView(threadId: thread.id)
            }
            .presentationDragIndicator(Visibility.visible)
            .appSheetBackground()
        }
        .sheet(item: $briefingThreadRoute) { route in
            NavigationStack {
                EmailThreadView(threadId: route.id)
            }
            .presentationDragIndicator(Visibility.visible)
            .appSheetBackground()
        }
        .sheet(item: $selectedFolder) { folder in
            NavigationStack {
                FolderDetailView(folder: folder)
            }
            .presentationDragIndicator(Visibility.visible)
            .appSheetBackground()
        }
        .sheet(isPresented: $showFolderEditSheet) {
            FolderEditSheet(mode: .create)
                .appSheetBackground()
        }
        // Header ellipsis menu — Refresh
        .onChange(of: services.homeRefreshTick) { _, _ in
            Task {
                await services.remindersSyncService.refreshFromReminders(in: modelContext)
                await loadHomeData()
                lastRefresh = Date()
            }
        }
    }

    /// Sheet route for opening a thread by id when we don't have the full EmailThread payload
    /// (briefing rows + hero priority callout).
    private struct HomeThreadIdRoute: Identifiable {
        let id: String
    }

    // MARK: - Time-aware briefing hero

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

    /// Time-aware one-line summary derived from today's counts. Falls back to a friendly
    /// "all clear" line when there's nothing to surface.
    private var summaryLine: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let eventCount = todaysEvents.count
        let taskCount = tasksDueToday.count
        let replyCount = services.emailService.assistantBriefing?.needsYou.count ?? 0

        var parts: [String] = []
        if eventCount > 0 {
            parts.append("\(eventCount) event\(eventCount == 1 ? "" : "s")")
        }
        if taskCount > 0 {
            parts.append("\(taskCount) task\(taskCount == 1 ? "" : "s") due")
        }
        if replyCount > 0 {
            parts.append("\(replyCount) repl\(replyCount == 1 ? "y" : "ies") waiting")
        }

        if parts.isEmpty {
            switch hour {
            case 5..<12: return "Your day looks clear."
            case 12..<17: return "Nothing on your plate right now."
            default: return "You're all caught up."
            }
        }

        let prefix: String
        switch hour {
        case 5..<12: prefix = "Today you have"
        case 12..<17: prefix = "Still on your plate:"
        default: prefix = "Outstanding for today:"
        }
        return "\(prefix) \(parts.joined(separator: ", "))."
    }

    /// Single highest-priority item to surface in the hero, picked in this order:
    /// urgent reply → top task → next event. Returns nil if briefing hasn't loaded.
    private var topPriority: HomeTopPriority? {
        guard let briefing = services.emailService.assistantBriefing else { return nil }
        if let urgent = briefing.today.urgentReply {
            return HomeTopPriority(
                kind: .reply,
                title: urgent.title,
                detail: urgent.summary,
                threadId: urgent.threadId
            )
        }
        if let topTask = briefing.today.topTask {
            return HomeTopPriority(
                kind: .task,
                title: topTask.title,
                detail: topTask.dueDate ?? "Top task",
                threadId: nil
            )
        }
        if let nextEvent = briefing.today.nextEvent {
            return HomeTopPriority(
                kind: .event,
                title: nextEvent.title,
                detail: nextEvent.startsAt,
                threadId: nil
            )
        }
        return nil
    }

    private struct HomeTopPriority {
        enum Kind {
            case reply, task, event
            var icon: String {
                switch self {
                case .reply: return "arrowshape.turn.up.left.fill"
                case .task: return "checkmark.circle.fill"
                case .event: return "calendar"
                }
            }
            var label: String {
                switch self {
                case .reply: return "Urgent reply"
                case .task: return "Top task"
                case .event: return "Next event"
                }
            }
        }
        let kind: Kind
        let title: String
        let detail: String
        let threadId: String?
    }

    private struct HomeStatChip: Identifiable {
        let id: String
        let icon: String
        let label: String
        let action: () -> Void
    }

    private var heroStatChips: [HomeStatChip] {
        var chips: [HomeStatChip] = []
        if !tasksDueToday.isEmpty {
            chips.append(HomeStatChip(
                id: "tasks",
                icon: "checkmark.circle",
                label: "\(tasksDueToday.count) task\(tasksDueToday.count == 1 ? "" : "s")",
                action: { services.navigateTo = .tasks }
            ))
        }
        let needsYouCount = services.emailService.assistantBriefing?.needsYou.count ?? 0
        if needsYouCount > 0 {
            chips.append(HomeStatChip(
                id: "needs-reply",
                icon: "arrowshape.turn.up.left",
                label: "\(needsYouCount) repl\(needsYouCount == 1 ? "y" : "ies")",
                action: { services.navigateTo = .email }
            ))
        }
        return chips
    }

    private var briefingHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(greeting)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary)
                    if isAssistantBriefingRefreshing {
                        InlineRefreshBadge()
                    }
                }
                Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(summaryLine)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let priority = topPriority {
                topPriorityRow(priority)
            }

            if !todaysEvents.isEmpty {
                VStack(spacing: 6) {
                    ForEach(todaysEvents.prefix(3)) { event in
                        Button {
                            selectedCalendarEvent = event
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color(hue: Double(event.calendarColor % 360) / 360.0, saturation: 0.6, brightness: 0.8))
                                    .frame(width: 7, height: 7)
                                Text(event.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
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
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.inline, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !heroStatChips.isEmpty {
                HStack(spacing: 8) {
                    ForEach(heroStatChips) { chip in
                        Button(action: chip.action) {
                            HStack(spacing: 6) {
                                Image(systemName: chip.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(chip.label)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppTheme.surfaceSecondary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }

    private func topPriorityRow(_ priority: HomeTopPriority) -> some View {
        Button {
            switch priority.kind {
            case .reply:
                if let id = priority.threadId {
                    briefingThreadRoute = HomeThreadIdRoute(id: id)
                } else {
                    services.navigateTo = .email
                }
            case .task:
                services.navigateTo = .tasks
            case .event:
                services.navigateTo = .calendar
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: priority.kind.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.inline, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(priority.kind.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.mutedText)
                        .textCase(.uppercase)
                    Text(priority.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if !priority.detail.isEmpty {
                        Text(priority.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Smart progressive setup checklist

    private var needsTaskSetup: Bool {
        allTasksIncludingCompleted.isEmpty
    }

    private var needsEmailSetup: Bool {
        hasLoadedEmailState && !services.emailService.hasConnection
    }

    private var needsCalendarSetup: Bool {
        !services.calendarService.canReadEvents()
    }

    private var showSetupChecklist: Bool {
        needsTaskSetup || needsEmailSetup || needsCalendarSetup
    }

    private var setupChecklist: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Finish setting up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            VStack(spacing: 8) {
                if needsTaskSetup {
                    setupChecklistRow(
                        icon: "checkmark.circle",
                        title: "Create your first task",
                        subtitle: "Tap + or open the Tasks tab",
                        action: { services.requestCreateSheet = .task }
                    )
                }
                if needsEmailSetup {
                    setupChecklistRow(
                        icon: "envelope.fill",
                        title: "Connect Gmail",
                        subtitle: "Bring your inbox into Home and Email",
                        action: { services.navigateTo = .email }
                    )
                }
                if needsCalendarSetup {
                    setupChecklistRow(
                        icon: "calendar",
                        title: "Enable calendar access",
                        subtitle: "See today's events alongside your tasks",
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

    private func setupChecklistRow(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
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

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Consolidated briefing feed

    private struct BriefingFeedItem: Identifiable {
        enum Category {
            case reply, waiting, draft
            var label: String {
                switch self {
                case .reply: return "Reply"
                case .waiting: return "Waiting"
                case .draft: return "Draft"
                }
            }
        }
        let id: String
        let category: Category
        let title: String
        let summary: String
        let threadId: String?
    }

    private var briefingFeedItems: [BriefingFeedItem] {
        guard let briefing = services.emailService.assistantBriefing else { return [] }
        var items: [BriefingFeedItem] = []
        for loop in briefing.needsYou {
            items.append(BriefingFeedItem(
                id: "needs-\(loop.id)",
                category: .reply,
                title: loop.title,
                summary: loop.summary,
                threadId: loop.threadId
            ))
        }
        for loop in briefing.waitingOn {
            items.append(BriefingFeedItem(
                id: "waiting-\(loop.id)",
                category: .waiting,
                title: loop.title,
                summary: loop.summary,
                threadId: loop.threadId
            ))
        }
        for action in briefing.prepared {
            items.append(BriefingFeedItem(
                id: "prepared-\(action.id)",
                category: .draft,
                title: action.title,
                summary: action.summary,
                threadId: action.threadId
            ))
        }
        return items
    }

    private var showBriefingFeed: Bool {
        guard services.assistantAutomationPolicy.briefingEnabled,
              services.assistantAutomationPolicy.showHomeBriefing else {
            return false
        }
        if !briefingFeedItems.isEmpty { return true }
        // Show loading skeleton on cold launch with no cache.
        if isLoadingAssistantBriefing && services.emailService.assistantBriefing == nil {
            return true
        }
        return false
    }

    private var briefingFeedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
                Text("Assistant Briefing")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if briefingFeedItems.count > 6 {
                    Button("View all") {
                        services.navigateTo = .email
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                }
            }

            if isLoadingAssistantBriefing && services.emailService.assistantBriefing == nil {
                loadingState(message: "Preparing your briefing")
            } else {
                VStack(spacing: 8) {
                    ForEach(briefingFeedItems.prefix(6)) { item in
                        briefingFeedRow(item)
                    }
                }
            }
        }
    }

    private func briefingFeedRow(_ item: BriefingFeedItem) -> some View {
        Button {
            if let id = item.threadId {
                briefingThreadRoute = HomeThreadIdRoute(id: id)
            } else {
                services.navigateTo = .email
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(item.category.label)
                    .font(.system(size: 10, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(AppTheme.mutedText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AppTheme.surfaceSecondary, in: Capsule())

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !item.summary.isEmpty {
                        Text(item.summary)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                count: services.emailService.threads.count,
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
                // Show 2 recent threads — the briefing already surfaces priority items.
                VStack(spacing: 8) {
                    ForEach(Array(services.emailService.threads.prefix(2))) { thread in
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

    // MARK: - Folders Section

    /// Horizontal scroller of folder cards. Always visible — surfaces folders as a
    /// first-class home concept rather than burying them behind the Tasks tab.
    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Folders",
                icon: "folder.fill",
                count: folders.count,
                actionTitle: "Manage",
                isUpdating: false,
                onOpen: { services.navigateTo = .tasks },
                onAdd: { showFolderEditSheet = true }
            )

            if folders.isEmpty {
                Button {
                    showFolderEditSheet = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.subtleText)
                        Text("Create your first folder to group emails, tasks, chats, and events.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.subtleText)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                            .fill(AppTheme.surfacePrimary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                            .strokeBorder(AppTheme.cardBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(folders) { folder in
                            Button {
                                selectedFolder = folder
                            } label: {
                                FolderCardView(folder: folder, layout: .horizontal)
                            }
                            .buttonStyle(.plain)
                        }
                        NewFolderCard(layout: .horizontal) {
                            showFolderEditSheet = true
                        }
                    }
                }
                // Bleed the scroller to the screen edge so cards feel pinned to the rail.
                .padding(.horizontal, -16)
                .scrollClipDisabled(true)
                .safeAreaPadding(.horizontal, 16)
            }
        }
    }

    // MARK: - More Section (pages not in the tab bar)

    /// Shows AppTab pages not pinned to the nav bar, plus the always-available Docs page.
    /// Keeps the tab bar lean while ensuring every part of the app is reachable from Home.
    @ViewBuilder
    private var moreSection: some View {
        let nativeTabs: Set<AppTab> = [.home, .tasks, .email, .calendar, .meetings]
        let extraTabs = AppTab.allCases.filter {
            !nativeTabs.contains($0) && $0 != .create && $0 != .ai
        }
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

                Text("Places outside the main tab bar")
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
        await services.captureService.syncSharedFolders(in: modelContext)
        await services.captureService.fetchFolderSummary(in: modelContext)

        if services.authService.isAuthenticated,
           services.emailService.hasConnection,
           services.assistantAutomationPolicy.assistantThreadActionsVisible,
           services.assistantAutomationPolicy.briefingEnabled {
            await services.emailService.loadAssistantNudges()
        }

        if services.assistantAutomationPolicy.briefingEnabled
            && services.assistantAutomationPolicy.showHomeBriefing {
            isLoadingAssistantBriefing = true
            _ = await services.emailService.loadAssistantBriefing()
            isLoadingAssistantBriefing = false
        }
    }
}

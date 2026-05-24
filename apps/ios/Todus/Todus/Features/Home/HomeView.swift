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

    @State private var upcomingEvents: [CalendarEvent] = []
    @State private var isLoadingEvents = false
    @State private var hasLoadedEmailState = false
    @State private var isLoadingAssistantBriefing = false

    // Sheet state
    @State private var selectedTask: TaskRecord? = nil
    @State private var selectedCalendarEvent: CalendarEvent? = nil
    @State private var selectedEmailThread: EmailThread? = nil
    /// Sheet for opening a thread by id — used by hero priority callout and briefing rows
    /// where we don't have the full EmailThread payload, only the id.
    @State private var briefingThreadRoute: HomeThreadIdRoute? = nil
    @State private var showDocsSheet = false
    @State private var meetingRoute: HomeMeetingRoute? = nil

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
                VStack(alignment: .leading, spacing: 22) {
                    slimGreeting

                    if showBriefingFeed {
                        todayList
                    }

                    if showSetupChecklist {
                        setupChecklist
                    }

                    upcomingTimelineSection
                    emailSection
                    meetingsSection

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
        .sheet(item: $meetingRoute) { route in
            NavigationStack {
                MeetingDetailView(meetingId: route.id)
            }
            .presentationDragIndicator(Visibility.visible)
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

    private struct HomeMeetingRoute: Identifiable {
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
        isLoadingEvents && !upcomingEvents.isEmpty
    }

    private var isEmailRefreshing: Bool {
        // Mirror the inbox view's badge condition so Home matches what Mail shows: the
        // "Updating" indicator is on while either the foreground load or the background
        // post-forceSync reconciliation is running.
        (services.emailService.isLoadingThreads || services.emailService.isReconciling)
            && !services.emailService.threads.isEmpty
    }

    /// Time-aware one-line summary derived from today's counts. Falls back to a friendly
    /// "all clear" line when there's nothing to surface.
    private var summaryLine: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let cal = Calendar.current
        let eventCount = upcomingEvents.filter { cal.isDateInToday($0.startDate) }.count
        let taskCount = allTasks.filter { !$0.completed && $0.dueDate.map { cal.isDateInToday($0) } == true }.count
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
    ///
    /// For `urgentReply` we show the email subject (`summary`) as the headline so the
    /// hero is identifiable at a glance — same flip-the-fields rule applied to the
    /// briefing feed. The AI's verb (`title`) becomes the secondary line.
    private var topPriority: HomeTopPriority? {
        guard let briefing = services.emailService.assistantBriefing else { return nil }
        if let urgent = briefing.today.urgentReply {
            let display = urgent.rowDisplay
            return HomeTopPriority(
                kind: .reply,
                title: display.headline,
                detail: display.caption,
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

    // MARK: - Unified timeline model

    private enum UpcomingTimelineItem: Identifiable {
        case event(CalendarEvent)
        case task(TaskRecord)

        var id: String {
            switch self {
            case .event(let e): return "event-\(e.id)"
            case .task(let t): return "task-\(t.id.uuidString)"
            }
        }
        var sortDate: Date {
            switch self {
            case .event(let e): return e.startDate
            case .task(let t): return t.dueDate ?? .distantFuture
            }
        }
    }

    private struct UpcomingDaySection: Identifiable {
        let id: Date      // start of day
        let dayName: String   // "Today", "Tomorrow", "Wednesday"
        let shortDate: String // "Mon 27 Apr"
        let isToday: Bool
        let items: [UpcomingTimelineItem]
    }

    private var upcomingTimelineSections: [UpcomingDaySection] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let cutoff = cal.date(byAdding: .day, value: 7, to: today) else { return [] }

        var byDay: [Date: [UpcomingTimelineItem]] = [:]

        for event in upcomingEvents {
            let day = cal.startOfDay(for: event.startDate)
            byDay[day, default: []].append(.event(event))
        }
        for task in allTasks where !task.completed {
            guard let due = task.dueDate, due >= today, due < cutoff else { continue }
            let day = cal.startOfDay(for: due)
            byDay[day, default: []].append(.task(task))
        }

        return byDay.keys.sorted().map { day in
            let isToday = cal.isDateInToday(day)
            let isTomorrow = cal.isDateInTomorrow(day)
            let diff = cal.dateComponents([.day], from: today, to: day).day ?? 0
            let dayName: String
            if isToday { dayName = "Today" }
            else if isTomorrow { dayName = "Tomorrow" }
            else if diff < 7 { dayName = day.formatted(.dateTime.weekday(.wide)) }
            else { dayName = day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
            let shortDate = day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            let sorted = (byDay[day] ?? []).sorted { $0.sortDate < $1.sortDate }
            return UpcomingDaySection(id: day, dayName: dayName, shortDate: shortDate, isToday: isToday, items: sorted)
        }
    }

    private var heroStatChips: [HomeStatChip] {
        var chips: [HomeStatChip] = []
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

    /// Quiet greeting line. No card, no chips, no summary count — the Today list
    /// directly below IS the count, and chips that navigate away from Home would
    /// directly contradict the "act from Home" intent.
    private var slimGreeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(greeting)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.primary)
                if isAssistantBriefingRefreshing {
                    InlineRefreshBadge()
                }
            }
            Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        /// Which bucket the row originated from — drives which trust-loop mutation
        /// runs when the user dismisses / snoozes.
        enum Source { case openLoop, preparedAction }
        let id: String
        let source: Source
        /// Server-side id (open-loop id or prepared-action id) used to call dismiss/snooze.
        let backendId: String
        let display: BriefingRowDisplay
        let threadId: String?
    }

    /// Items rendered in the Today list. Verb-first action sentences from the
    /// briefing, ranked + deduped + capped at 5.
    ///
    /// **Ranking** (top → bottom):
    /// 1. `today.urgentReply` — pinned first when present.
    /// 2. `prepared` drafts of type `draft_reply` with confidence ≥ 70 — "almost
    ///    done, just press send" beats new asks.
    /// 3. Other `prepared` rows.
    /// 4. `needsYou` open-loops (skipping urgent reply + already-prepared threads).
    ///
    /// **Dedupe**: by `threadId` against all earlier rows. `waitingOn` is
    /// deliberately excluded — it's noise for an action-oriented list, exposed
    /// elsewhere via the Mail tab when the user wants it.
    private var briefingFeedItems: [BriefingFeedItem] {
        guard let briefing = services.emailService.assistantBriefing else { return [] }

        var items: [BriefingFeedItem] = []
        var seenThreadIds = Set<String>()
        var seenBackendIds = Set<String>()

        func push(_ item: BriefingFeedItem) {
            if seenBackendIds.contains(item.backendId) { return }
            if let tid = item.threadId, !tid.isEmpty {
                if seenThreadIds.contains(tid) { return }
                seenThreadIds.insert(tid)
            }
            seenBackendIds.insert(item.backendId)
            items.append(item)
        }

        // 1. Urgent reply, pinned first.
        if let urgent = briefing.today.urgentReply {
            push(BriefingFeedItem(
                id: "urgent-\(urgent.id)",
                source: .openLoop,
                backendId: urgent.id,
                display: urgent.rowDisplay,
                threadId: urgent.threadId
            ))
        }

        // 2. High-confidence drafts — confidence on the model is 0.0…1.0.
        for action in briefing.prepared where action.type == "draft_reply" && action.confidence >= 0.70 {
            push(BriefingFeedItem(
                id: "prepared-\(action.id)",
                source: .preparedAction,
                backendId: action.id,
                display: action.rowDisplay,
                threadId: action.threadId
            ))
        }

        // 3. Remaining prepared items.
        for action in briefing.prepared where !(action.type == "draft_reply" && action.confidence >= 0.70) {
            push(BriefingFeedItem(
                id: "prepared-\(action.id)",
                source: .preparedAction,
                backendId: action.id,
                display: action.rowDisplay,
                threadId: action.threadId
            ))
        }

        // 4. NeedsYou — actionable open-loops.
        for loop in briefing.needsYou {
            push(BriefingFeedItem(
                id: "needs-\(loop.id)",
                source: .openLoop,
                backendId: loop.id,
                display: loop.rowDisplay,
                threadId: loop.threadId
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

    /// The "Today" list — verb-first action sentences, max 5, flat layout.
    /// Replaces the previous three-rail briefing dashboard. Each row is a single
    /// sentence ("Reply to Sarah about the Q4 proposal"), separated by a hairline
    /// divider — no per-row card backgrounds, no tinted badges.
    private var todayList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Today")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                if briefingFeedItems.count > 5 {
                    Button("Mail") {
                        services.navigateTo = .email
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                }
            }

            if isLoadingAssistantBriefing && services.emailService.assistantBriefing == nil {
                loadingState(message: "Preparing your day")
            } else if briefingFeedItems.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(AppTheme.mutedText)
                    Text("You're caught up.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 18)
            } else {
                VStack(spacing: 0) {
                    let items = Array(briefingFeedItems.prefix(5).enumerated())
                    ForEach(items, id: \.element.id) { pair in
                        todayRow(pair.element)
                        if pair.offset < items.count - 1 {
                            Divider()
                                .padding(.leading, 36)
                        }
                    }
                }
            }
        }
    }

    /// SF Symbol for a row's badge category. Replaces the previous tinted capsule —
    /// shape carries the type so VoiceOver users and color-blind users get the
    /// same signal as sighted ones.
    private func glyph(for badge: BriefingRowDisplay.Badge) -> String {
        switch badge {
        case .reply: return "arrowshape.turn.up.left"
        case .draft: return "paperplane"
        case .waiting: return "hourglass"
        case .research: return "magnifyingglass"
        case .task: return "checkmark.circle"
        case .event: return "calendar"
        case .followUp: return "arrow.forward.circle"
        case .other: return "circle.dotted"
        }
    }

    /// Accessibility verb mapped from badge — read first by VoiceOver before the
    /// sentence so the row's intent is immediately announced.
    private func accessibilityVerb(for badge: BriefingRowDisplay.Badge) -> String {
        switch badge {
        case .reply: return "Reply"
        case .draft: return "Send draft"
        case .waiting: return "Waiting on"
        case .research: return "Research"
        case .task: return "Task"
        case .event: return "Event"
        case .followUp: return "Follow up"
        case .other: return "Action"
        }
    }

    /// Flat, full-width row: leading glyph + verb-first sentence + meta line +
    /// trailing menu. No card background, no border — separation comes from the
    /// list-level Divider in `todayList`. Swipe + context menu provide quick
    /// snooze / dismiss / done without forcing the user into the trailing menu.
    private func todayRow(_ item: BriefingFeedItem) -> some View {
        let primary = todayPrimaryLine(item)
        let meta = todayMetaLine(item)
        return Button {
            openBriefingItem(item)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: glyph(for: item.display.badge))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(item.display.badge == .draft || item.display.badge == .reply
                                    ? AppTheme.accent : AppTheme.mutedText)
                    .frame(width: 24, height: 24, alignment: .center)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(primary)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Menu {
                    briefingRowActionMenu(for: item)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.mutedText)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More actions")
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(accessibilityVerb(for: item.display.badge)). \(primary). \(meta)")
        .contextMenu {
            briefingRowActionMenu(for: item)
        }
    }

    /// Primary headline for a Today row. Prefers the LLM-generated `actionLine`
    /// (a verb-first sentence). Falls back to the existing `headline` (email
    /// subject) when the backend hasn't populated `actionLine` for this row.
    private func todayPrimaryLine(_ item: BriefingFeedItem) -> String {
        if let line = todayActionLine(item), !line.isEmpty {
            return line
        }
        // Legacy fallback path: combine the AI verb hint and subject into one
        // sentence — "Reply needed: <subject>" — so even pre-actionLine data
        // reads as actionable instead of restating just the subject.
        let verbHint = item.display.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = item.display.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        if !verbHint.isEmpty && !subject.isEmpty {
            return "\(verbHint): \(subject)"
        }
        return subject.isEmpty ? verbHint : subject
    }

    /// Resolve `actionLine` off the underlying open-loop or prepared-action
    /// referenced by this briefing item.
    private func todayActionLine(_ item: BriefingFeedItem) -> String? {
        guard let briefing = services.emailService.assistantBriefing else { return nil }
        switch item.source {
        case .openLoop:
            let pool = briefing.needsYou + briefing.waitingOn
            if let loop = pool.first(where: { $0.id == item.backendId }) {
                return loop.actionLine?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let urgent = briefing.today.urgentReply, urgent.id == item.backendId {
                return urgent.actionLine?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        case .preparedAction:
            return briefing.prepared
                .first(where: { $0.id == item.backendId })?
                .actionLine?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Meta line — sender + age, kept short. Falls back to the AI verb caption
    /// when no sender is known.
    private func todayMetaLine(_ item: BriefingFeedItem) -> String {
        if let line = todayActionLine(item), !line.isEmpty {
            // actionLine carries the sender; meta is the subject (truncated).
            let subject = item.display.headline.trimmingCharacters(in: .whitespacesAndNewlines)
            return subject
        }
        return item.display.caption
    }

    @ViewBuilder
    private func briefingRowActionMenu(for item: BriefingFeedItem) -> some View {
        Button {
            openBriefingItem(item)
        } label: {
            Label("Open thread", systemImage: "arrow.up.right.square")
        }

        Button {
            Task { await markBriefingItemDone(item) }
        } label: {
            Label("Mark done", systemImage: "checkmark.circle")
        }

        Menu {
            ForEach(snoozePresets, id: \.label) { preset in
                Button(preset.label) {
                    Task { await snoozeBriefingItem(item, until: preset.date()) }
                }
            }
        } label: {
            Label("Snooze", systemImage: "clock")
        }

        Divider()

        // Destructive — labeled honestly: this is a "this isn't a reply" / training signal.
        Button(role: .destructive) {
            Task { await dismissBriefingItem(item) }
        } label: {
            Label(item.source == .preparedAction ? "Not a draft I want" : "Not a reply", systemImage: "xmark.circle")
        }
    }

    private struct SnoozePreset {
        let label: String
        let date: () -> Date
    }
    private var snoozePresets: [SnoozePreset] {
        [
            SnoozePreset(label: "Later today") { Calendar.current.date(byAdding: .hour, value: 4, to: Date()) ?? Date() },
            SnoozePreset(label: "Tomorrow morning") {
                let cal = Calendar.current
                let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
            },
            SnoozePreset(label: "Next week") { Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date() },
        ]
    }

    private func openBriefingItem(_ item: BriefingFeedItem) {
        if let id = item.threadId {
            briefingThreadRoute = HomeThreadIdRoute(id: id)
        } else {
            services.navigateTo = .email
        }
    }

    private func dismissBriefingItem(_ item: BriefingFeedItem) async {
        switch item.source {
        case .openLoop:
            await services.emailService.dismissBriefingOpenLoop(id: item.backendId, threadId: item.threadId)
        case .preparedAction:
            await services.emailService.dismissBriefingPreparedAction(id: item.backendId, threadId: item.threadId)
        }
    }

    private func markBriefingItemDone(_ item: BriefingFeedItem) async {
        switch item.source {
        case .openLoop:
            await services.emailService.completeBriefingOpenLoop(id: item.backendId, threadId: item.threadId)
        case .preparedAction:
            // No "done" semantic for prepared actions — the right UX is "apply" or "dismiss".
            // Treat "Mark done" on a prepared action as a soft dismiss with `completed` feedback.
            await services.emailService.dismissBriefingPreparedAction(id: item.backendId, threadId: item.threadId, feedback: "completed")
        }
    }

    private func snoozeBriefingItem(_ item: BriefingFeedItem, until: Date) async {
        switch item.source {
        case .openLoop:
            await services.emailService.snoozeBriefingOpenLoop(id: item.backendId, threadId: item.threadId, until: until)
        case .preparedAction:
            // No backend snooze for prepared actions today — fall back to a local hide
            // (`dismiss` with `helpful` feedback so the classifier doesn't downweight).
            await services.emailService.dismissBriefingPreparedAction(id: item.backendId, threadId: item.threadId, feedback: "helpful")
        }
    }

    // MARK: - Unified Timeline Section

    private var upcomingTimelineSection: some View {
        let sections = upcomingTimelineSections
        let totalCount = sections.reduce(0) { $0 + $1.items.count }
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "This Week",
                icon: "calendar",
                count: totalCount,
                actionTitle: "Open",
                isUpdating: isEventsRefreshing,
                onOpen: { services.navigateTo = .calendar },
                onAdd: { services.requestCreateSheet = .event }
            )

            if isLoadingEvents && upcomingEvents.isEmpty && sections.isEmpty {
                loadingState(message: "Loading your week")
            } else if !services.calendarService.canReadEvents() && sections.isEmpty {
                permissionEmptyState(
                    message: "Enable calendar access in Settings to see upcoming events",
                    actionTitle: "Open Settings"
                )
            } else if sections.isEmpty {
                emptyState(message: "Nothing coming up this week", onTap: { services.navigateTo = .calendar })
            } else {
                VStack(spacing: 10) {
                    ForEach(sections) { section in
                        timelineDayCard(section)
                    }
                }
            }
        }
    }

    private func timelineDayCard(_ section: UpcomingDaySection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Day header strip
            HStack(spacing: 5) {
                Text(section.dayName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(section.isToday ? AppTheme.accent : .secondary)
                Text("·")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Text(section.shortDate)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(section.items.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(section.isToday ? AppTheme.accent.opacity(0.07) : AppTheme.surfaceSecondary)

            // Items
            ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider()
                        .padding(.leading, 36)
                }
                timelineItemRow(item)
            }
        }
        .background(AppTheme.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                .stroke(section.isToday ? AppTheme.accent.opacity(0.3) : AppTheme.cardBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func timelineItemRow(_ item: UpcomingTimelineItem) -> some View {
        switch item {
        case .event(let event):
            Button { selectedCalendarEvent = event } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(red: event.calendarColorRed, green: event.calendarColorGreen, blue: event.calendarColorBlue))
                        .frame(width: 8, height: 8)
                        .padding(.leading, 4)
                    Text(event.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text(event.isAllDay ? "All day" : event.startDate.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Unfiled") { moveEvent(event, to: nil) }
                if !folders.isEmpty { Divider() }
                ForEach(folders) { folder in Button(folder.name) { moveEvent(event, to: folder.id) } }
            }

        case .task(let task):
            Button { selectedTask = task } label: {
                HStack(spacing: 12) {
                    Circle()
                        .foregroundStyle(.tertiary)
                        .frame(width: 8, height: 8)
                        .padding(.leading, 4)
                    Text(task.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func folderName(for folderID: UUID?) -> String? {
        guard let folderID else { return nil }
        return folders.first(where: { $0.id == folderID })?.name
    }

    private func moveEvent(_ event: CalendarEvent, to folderID: UUID?) {
        Task {
            await services.calendarService.setFolderID(folderID, for: event.id)
            await loadUpcomingEvents()
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
                // Cold-launch: three ghost rows convey "this list is loading" without
                // the dead-air feel of a single spinner row. The actual email rows
                // pop into place once the connection probe + reconcile complete.
                emailSkeletonRows
            } else if !services.emailService.hasConnection {
                // Not connected — prompt to connect
                emptyState(
                    message: "Connect Gmail to see your inbox",
                    onTap: { services.navigateTo = .email }
                )
            } else if (services.emailService.isLoadingThreads
                || services.emailService.isReconciling)
                && services.emailService.threads.isEmpty {
                // Initial load OR post-forceSync reconciliation — show the loading copy so
                // a user with an empty backend DB doesn't see "No recent emails" mid-sync.
                loadingState(message: "Loading recent emails")
            } else if services.emailService.threads.isEmpty {
                // Connected but no emails loaded yet
                emptyState(
                    message: "No recent emails",
                    onTap: { services.navigateTo = .email }
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(services.emailService.threads.prefix(5))) { thread in
                        Button {
                            selectedEmailThread = thread
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                // Unread indicator dot — top-aligned with the sender line
                                Circle()
                                    .fill(thread.unread ? Color.primary : Color.clear)
                                    .frame(width: 7, height: 7)
                                    .padding(.top, 5)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(thread.from.name)
                                            .font(.system(size: 14, weight: thread.unread ? .bold : .medium))
                                            .lineLimit(1)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text(emailTimeLabel(thread.date))
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(thread.subject)
                                        .font(.system(size: 13, weight: thread.unread ? .semibold : .medium))
                                        .lineLimit(1)
                                        .foregroundStyle(.primary.opacity(0.85))
                                    if !thread.snippet.isEmpty {
                                        Text(thread.snippet)
                                            .font(.system(size: 12))
                                            .lineLimit(2)
                                            .foregroundStyle(.secondary)
                                    }
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

    // MARK: - Meetings Section

    private var meetingsSection: some View {
        let allMeetings = services.meetingsService.meetings
        let displayMeetings: [MeetingItem] = {
            let cal = Calendar.current
            let todayStart = cal.startOfDay(for: Date())
            let upcoming = allMeetings.filter { $0.startsAt >= todayStart }
            return Array((upcoming.isEmpty ? allMeetings : upcoming).prefix(3))
        }()

        return VStack(alignment: .leading, spacing: 12) {
            meetingsSectionHeader(count: allMeetings.count)

            if services.meetingsService.isLoading && allMeetings.isEmpty {
                loadingState(message: "Loading meetings")
            } else if allMeetings.isEmpty {
                Button {
                    Task { await services.meetingsService.syncFromCalendar() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: services.meetingsService.isSyncing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.subtleText)
                        Text(services.meetingsService.isSyncing ? "Syncing calendar…" : "Sync Google Calendar to import meetings")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.subtleText)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                            .strokeBorder(AppTheme.cardBorder, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(services.meetingsService.isSyncing)
            } else {
                VStack(spacing: 8) {
                    ForEach(displayMeetings) { meeting in
                        Button {
                            meetingRoute = HomeMeetingRoute(id: meeting.id)
                        } label: {
                            homeMeetingRow(meeting)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func meetingsSectionHeader(count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "video.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Meetings")
                .font(.system(size: 15, weight: .semibold))
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.surfaceSecondary, in: Capsule())
            }
            if services.meetingsService.isSyncing {
                InlineRefreshBadge()
            }
            Spacer()

            Button("View all") {
                services.navigateToSheet = .meetings
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.accent)

            Button {
                Task { await services.meetingsService.syncFromCalendar() }
            } label: {
                Image(systemName: "arrow.clockwise")
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
            .disabled(services.meetingsService.isSyncing)
        }
    }

    private func homeMeetingRow(_ meeting: MeetingItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: homeMeetingStatusIcon(meeting.status))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(homeMeetingStatusColor(meeting.status))
                .frame(width: 28, height: 28)
                .background(homeMeetingStatusColor(meeting.status).opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(meeting.startsAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if meeting.aiSummary != nil {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.5))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    private func homeMeetingStatusIcon(_ status: String) -> String {
        switch status {
        case "scheduled": return "calendar"
        case "bot_joining", "processing": return "arrow.triangle.2.circlepath"
        case "recording": return "record.circle"
        case "ready": return "checkmark.circle"
        case "failed": return "exclamationmark.triangle"
        case "cancelled": return "xmark.circle"
        default: return "circle"
        }
    }

    private func homeMeetingStatusColor(_ status: String) -> Color {
        switch status {
        case "scheduled": return .primary
        case "bot_joining", "processing": return .orange
        case "recording": return .red
        case "ready": return .green
        case "failed": return .red
        case "cancelled": return .gray
        default: return .secondary
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
        let nativeTabs: Set<AppTab> = [.home, .tasks, .email, .calendar, .meetings, .docs]
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
        Button { services.navigateTo = .docs } label: {
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
        // Animated dotted text — "Loading recent emails…" → "Almost there" after 2s.
        // Reassurance copy on cold-launch when the user is staring at a spinner
        // wondering whether anything is happening.
        ProgressiveLoadingRow(initialMessage: message)
    }

    /// Three faint placeholder rows shaped roughly like real email rows. Pure
    /// SwiftUI — no animation library required. The gentle redraw pulse from
    /// `RoundedRectangle.fill(.secondary.opacity(...))` plus the cached blur
    /// material is enough to read as "loading", without the heavy shimmer libs.
    private var emailSkeletonRows: some View {
        VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: 7, height: 7)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.18))
                            .frame(width: 140, height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.14))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 10)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.10))
                            .frame(maxWidth: 220, alignment: .leading)
                            .frame(height: 10)
                    }
                }
                .padding(12)
                .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading recent emails")
    }

    /// Human-readable time label for an email: "5m ago", "2h ago", "Yesterday", or "Apr 23".
    private func emailTimeLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let seconds = Int(Date().timeIntervalSince(date))
            if seconds < 90 { return "Just now" }
            let mins = seconds / 60
            if mins < 60 { return "\(mins)m ago" }
            return "\(mins / 60)h ago"
        }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func loadUpcomingEvents() async {
        let trace = PerformanceTrace.beginInterval(
            PerformanceTrace.loadTodayEvents,
            message: "HomeView.loadUpcomingEvents begin"
        )
        isLoadingEvents = true
        defer {
            isLoadingEvents = false
            PerformanceTrace.endInterval(
                PerformanceTrace.loadTodayEvents,
                trace,
                message: "HomeView.loadUpcomingEvents end count=\(upcomingEvents.count)"
            )
        }
        if services.calendarService.canReadEvents() {
            let now = Date()
            upcomingEvents = await services.calendarService.upcomingEvents(days: 7)
                .filter { event in
                    // All-day events span the full day — always keep them
                    if event.isAllDay { return true }
                    // Timed events: skip if already over
                    return event.endDate > now
                }
                .sorted { $0.startDate < $1.startDate }
        }
    }

    private func loadHomeData() async {
        await services.emailService.checkConnection()
        hasLoadedEmailState = true

        if services.emailService.hasConnection {
            await services.emailService.ensureInitialInboxLoaded()
        }

        await loadUpcomingEvents()
        await services.meetingsService.loadMeetings()
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

// MARK: - ProgressiveLoadingRow

/// Loading row whose copy progresses over time so a slow request feels less
/// stuck. Starts with the caller-provided message, then swaps to a reassurance
/// string after 2s. Spinner uses `@ScaledMetric` so it tracks Dynamic Type.
private struct ProgressiveLoadingRow: View {
    let initialMessage: String

    @State private var hasReassured = false
    @ScaledMetric(relativeTo: .body) private var spinnerSize: CGFloat = 16

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.regular)
                .frame(width: spinnerSize, height: spinnerSize)
            Text(displayMessage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .animation(.easeInOut(duration: 0.25), value: hasReassured)
            Spacer()
        }
        .padding(14)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
        .task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            // Don't swap the copy if the row was removed in the meantime — the
            // .task cancellation propagates here so `hasReassured` only flips
            // when the user actually waited the full window.
            guard !Task.isCancelled else { return }
            hasReassured = true
        }
    }

    private var displayMessage: String {
        hasReassured ? "Almost there…" : "\(initialMessage)…"
    }
}

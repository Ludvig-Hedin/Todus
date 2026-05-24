import AppKit
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

    /// Called when the user taps a briefing row tied to a specific email thread.
    /// Hosts can wire this to open the thread sheet directly; falls back to
    /// `onNavigate(.email(.inbox))` when nil so the row never becomes a dead tap.
    var onNavigateEmailThread: ((String) -> Void)? = nil

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
    /// Guards the empty-state "Connect Gmail" button so spam-clicks during the
    /// OAuth round-trip don't queue duplicate `connectGmail` calls.
    @State private var isConnectingGmail = false
    @State private var selectedCalendarEvent: CalendarEvent? = nil
    @State private var selectedUpcomingEvent: CalendarEvent? = nil
    @State private var selectedTask: TaskRecord? = nil
    @State private var selectedMeetingId: IdentifiableString? = nil
    @State private var setupBannerDismissed = false

    private var isAssistantBriefingRefreshing: Bool {
        isLoadingAssistantBriefing && services.emailService.assistantBriefing != nil
    }

    private var isEventsRefreshing: Bool {
        isLoadingEvents && !todaysEvents.isEmpty
    }

    private var isEmailRefreshing: Bool {
        (services.emailService.isLoadingThreads || services.emailService.isReconciling)
            && !services.emailService.threads.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Greeting header
            greetingHeader
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
                VStack(alignment: .leading, spacing: MacTheme.spacing20) {
                    HStack(alignment: .top, spacing: MacTheme.spacing20) {
                        tasksColumn
                        eventsColumn
                    }
                    HStack(alignment: .top, spacing: MacTheme.spacing20) {
                        emailsSection
                        scheduleSidebar
                    }
                }
                .padding(.bottom, MacTheme.spacing24)
            }
        }
        .task {
            await loadCalendarData()
            await services.emailService.checkConnection()
            if services.emailService.hasConnection {
                // Always trigger a Gmail re-sync on Home appearance — without this, returning
                // users see whatever stale rows the backend last persisted (was the
                // "month-old emails" symptom on iOS too). The forceSyncCooldown coalesces
                // this with the inbox view's polling so we don't double-wipe the DB.
                if services.emailService.threads.isEmpty {
                    await services.emailService.loadThreads(refresh: true, triggerSync: true)
                } else {
                    Task { [services] in
                        await services.emailService.loadThreads(refresh: true, triggerSync: true)
                    }
                }
            }
            if services.authService.isAuthenticated {
                await services.meetingsService.loadMeetings()
            }
            if services.assistantAutomationPolicy.briefingEnabled
                && services.assistantAutomationPolicy.showHomeBriefing {
                isLoadingAssistantBriefing = true
                _ = await services.emailService.loadAssistantBriefing()
                isLoadingAssistantBriefing = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Mirror the inbox view's behavior so Home auto-updates when the user returns
            // to the app, even if they never visit the Mail tab.
            guard services.emailService.hasConnection,
                  !services.emailService.isLoadingThreads,
                  !services.emailService.isReconciling
            else { return }
            Task { [services] in
                await services.emailService.loadThreads(refresh: true, triggerSync: true)
            }
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
        !setupBannerDismissed
            && !(todaysEvents.isEmpty && orderedPreviewTasks.isEmpty && !services.emailService.hasConnection)
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

    /// Total actionable items in the briefing — fed to the section header badge.
    /// Previously showed `topPriorities.count` (≈3) which mismatched what the user saw
    /// (10+ items across columns). Now it counts what's actually rendered after dedupe
    /// so the badge is honest.
    private var assistantBriefingPriorityCount: Int {
        guard let briefing = services.emailService.assistantBriefing else { return 0 }
        let needsYouCount = dedupedOpenLoopRows(briefing.needsYou, briefing: briefing).count
        let waitingOnCount = dedupedOpenLoopRows(briefing.waitingOn, briefing: briefing).count
        return briefing.prepared.count + needsYouCount + waitingOnCount
    }

    /// Drop open-loop rows whose thread already appears as a Prepared (draft-ready)
    /// row. Without this, the same thread shows up in two columns with near-identical
    /// content — confusing and wasteful. Drafts win because they're "almost done."
    private func dedupedOpenLoopRows(_ loops: [AssistantOpenLoop], briefing: AssistantBriefing) -> [AssistantOpenLoop] {
        let preparedThreadIds = Set(briefing.prepared.compactMap { $0.threadId })
        return loops.filter { loop in
            guard let tid = loop.threadId else { return true }
            return !preparedThreadIds.contains(tid)
        }
    }

    private var emailSectionSubtitle: String {
        if !services.emailService.hasConnection {
            return "Connect Gmail to load a short inbox preview on Home."
        }
        if services.emailService.threads.isEmpty {
            return "Threads from your inbox will show here after the first sync."
        }
        return "Latest threads from your inbox."
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

            Button {
                setupBannerDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MacTheme.mutedText)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
        }
        .padding(MacTheme.spacing16)
        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
    }

    /// Source of a briefing row — drives the trust-loop mutation when dismissed.
    private enum MacBriefingRowSource { case openLoop, preparedAction }

    /// Pre-rendered row used by the queue columns. Computed once per render so the
    /// dedupe + display flip happens in one place.
    private struct MacBriefingRow: Identifiable {
        let id: String
        let backendId: String
        let source: MacBriefingRowSource
        let display: BriefingRowDisplay
        let threadId: String?
        /// LLM-generated verb-first sentence; nil → fall back to subject/title.
        let actionLine: String?
    }

    private var assistantBriefingSection: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing8) {
            HStack(spacing: MacTheme.spacing8) {
                Text("Today")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacTheme.textSecondary)
                    .tracking(0.6)
                    .textCase(.uppercase)
                if isAssistantBriefingRefreshing {
                    ProgressView().controlSize(.mini)
                }
                Spacer()
                if macTodayItems.count > 5 {
                    Button("Open Mail") { onNavigate?(.email(.inbox)) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MacTheme.accent)
                }
            }

            if isLoadingAssistantBriefing && services.emailService.assistantBriefing == nil {
                loadingCard(message: "Preparing your day")
            } else if macTodayItems.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(MacTheme.mutedText)
                    Text("You're caught up.")
                        .font(.system(size: 13))
                        .foregroundStyle(MacTheme.textSecondary)
                    Spacer()
                }
                .padding(.vertical, MacTheme.spacing16)
            } else {
                VStack(spacing: 0) {
                    let items = Array(macTodayItems.prefix(5).enumerated())
                    ForEach(items, id: \.element.id) { pair in
                        macTodayRow(pair.element)
                        if pair.offset < items.count - 1 {
                            Divider().padding(.leading, 32)
                        }
                    }
                }
            }
        }
    }

    /// Today list ranking — verb-first action sentences, max 5.
    /// Same logic as iOS `briefingFeedItems`: urgent reply pinned first,
    /// high-confidence drafts next, then remaining prepared items, then
    /// needsYou open-loops. Dedupe by `threadId` against earlier rows.
    /// `waitingOn` deliberately excluded — it's noise for action-oriented users.
    private var macTodayItems: [MacBriefingRow] {
        guard let briefing = services.emailService.assistantBriefing else { return [] }
        var items: [MacBriefingRow] = []
        var seenThreadIds = Set<String>()
        var seenBackendIds = Set<String>()

        func push(_ row: MacBriefingRow) {
            if seenBackendIds.contains(row.backendId) { return }
            if let tid = row.threadId, !tid.isEmpty {
                if seenThreadIds.contains(tid) { return }
                seenThreadIds.insert(tid)
            }
            seenBackendIds.insert(row.backendId)
            items.append(row)
        }

        if let urgent = briefing.today.urgentReply {
            push(MacBriefingRow(
                id: "urgent-\(urgent.id)",
                backendId: urgent.id,
                source: .openLoop,
                display: urgent.rowDisplay,
                threadId: urgent.threadId,
                actionLine: urgent.actionLine
            ))
        }
        for action in briefing.prepared where action.type == "draft_reply" && action.confidence >= 0.70 {
            push(MacBriefingRow(
                id: "prepared-\(action.id)",
                backendId: action.id,
                source: .preparedAction,
                display: action.rowDisplay,
                threadId: action.threadId,
                actionLine: action.actionLine
            ))
        }
        for action in briefing.prepared where !(action.type == "draft_reply" && action.confidence >= 0.70) {
            push(MacBriefingRow(
                id: "prepared-\(action.id)",
                backendId: action.id,
                source: .preparedAction,
                display: action.rowDisplay,
                threadId: action.threadId,
                actionLine: action.actionLine
            ))
        }
        for loop in briefing.needsYou {
            push(MacBriefingRow(
                id: "needs-\(loop.id)",
                backendId: loop.id,
                source: .openLoop,
                display: loop.rowDisplay,
                threadId: loop.threadId,
                actionLine: loop.actionLine
            ))
        }
        return items
    }

    private func macGlyph(for badge: BriefingRowDisplay.Badge) -> String {
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

    /// Resolve primary line: prefer `actionLine`, fall back to AI verb hint +
    /// subject. Matches iOS `todayPrimaryLine`.
    private func macPrimaryLine(_ row: MacBriefingRow) -> String {
        if let line = row.actionLine?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
            return line
        }
        let verbHint = row.display.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = row.display.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        if !verbHint.isEmpty && !subject.isEmpty {
            return "\(verbHint): \(subject)"
        }
        return subject.isEmpty ? verbHint : subject
    }

    /// Meta line — short subject (when actionLine carries the verb) or AI verb.
    private func macMetaLine(_ row: MacBriefingRow) -> String {
        if let line = row.actionLine?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
            return row.display.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return row.display.caption
    }

    /// Flat row: SF Symbol + verb-first sentence + meta + ellipsis. No card.
    private func macTodayRow(_ row: MacBriefingRow) -> some View {
        let primary = macPrimaryLine(row)
        let meta = macMetaLine(row)
        return HoverableRow(action: { openMacBriefingRow(row) }) { isHovering in
            HStack(alignment: .top, spacing: MacTheme.spacing12) {
                Image(systemName: macGlyph(for: row.display.badge))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(row.display.badge == .draft || row.display.badge == .reply
                                     ? MacTheme.accent : MacTheme.mutedText)
                    .frame(width: 20, height: 20, alignment: .center)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(primary)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(MacTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.system(size: 11.5))
                            .foregroundStyle(MacTheme.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: MacTheme.spacing8)

                // Hover-revealed action strip — Things-3 style. Keeps the row
                // visually quiet until the user actually wants to act.
                HStack(spacing: 6) {
                    if isHovering {
                        macRowActionButton(systemImage: "checkmark", tooltip: "Mark done") {
                            Task { await markMacBriefingRowDone(row) }
                        }
                        macRowActionButton(systemImage: "clock", tooltip: "Snooze later today") {
                            let date = Calendar.current.date(byAdding: .hour, value: 4, to: Date()) ?? Date()
                            Task { await snoozeMacBriefingRow(row, until: date) }
                        }
                        macRowActionButton(systemImage: "xmark", tooltip: "Dismiss") {
                            Task { await dismissMacBriefingRow(row) }
                        }
                    }
                    Menu {
                        macBriefingRowMenu(for: row)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MacTheme.mutedText)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("More actions")
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .contextMenu {
            macBriefingRowMenu(for: row)
        }
    }

    private func macRowActionButton(systemImage: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MacTheme.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    // TODO(bug-hunt): Dead code — assistantPriorityStrip is never called. Was part of an older
    // three-card priority strip UI replaced by macTodayRow. Safe to delete.
    private func assistantPriorityStrip(_ briefing: AssistantBriefing) -> some View {
        HStack(spacing: MacTheme.spacing8) {
            if let urgentReply = briefing.today.urgentReply {
                // Show the email subject (`summary`) as the prominent line, not the
                // AI verb. Same flip-the-fields rule we apply to feed rows.
                assistantPriorityCard(title: "Urgent reply", detail: urgentReply.rowDisplay.headline)
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

    // TODO(bug-hunt): Dead code — assistantQueueColumn and macBriefingRowCard are never called.
    // Remnants of the previous three-column briefing layout. Safe to delete both.
    private func assistantQueueColumn(title: String, rows: [MacBriefingRow]) -> some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing8) {
            HStack(spacing: MacTheme.spacing6) {
                Text(title)
                    .font(MacTheme.sectionHeaderFont())
                    .foregroundStyle(MacTheme.textPrimary)
                Text("\(rows.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(MacTheme.textSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(MacTheme.badgeSurface, in: RoundedRectangle(cornerRadius: MacTheme.pillRadius, style: .continuous))
                Spacer()
            }

            VStack(spacing: MacTheme.spacing6) {
                ForEach(rows.prefix(3)) { row in
                    macBriefingRowCard(row)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// Tint per badge — gives each category a stable visual identifier without
    /// breaking the editorial monochrome look.
    private func macBadgeTint(_ kind: BriefingRowDisplay.Badge) -> Color {
        switch kind {
        case .reply: return MacTheme.accent
        case .draft: return Color(red: 0.40, green: 0.65, blue: 0.45) // soft green
        case .waiting: return MacTheme.mutedText
        case .research: return Color(red: 0.55, green: 0.45, blue: 0.75)
        case .task: return Color(red: 0.85, green: 0.55, blue: 0.20)
        case .event: return MacTheme.accent
        case .followUp: return MacTheme.mutedText
        case .other: return MacTheme.mutedText
        }
    }

    private func macBriefingRowCard(_ row: MacBriefingRow) -> some View {
        let tint = macBadgeTint(row.display.badge)
        return Button {
            openMacBriefingRow(row)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // Top: tinted badge + AI verb caption (small, subordinate to subject below)
                HStack(alignment: .center, spacing: 6) {
                    Text(row.display.badge.label)
                        .font(.system(size: 9.5, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundStyle(tint)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: MacTheme.pillRadius, style: .continuous))

                    if !row.display.caption.isEmpty {
                        Text(row.display.caption)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MacTheme.mutedText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                // Email subject — the user's mental anchor. Most prominent in the row.
                Text(row.display.headline)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(MacTheme.spacing12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointerStyle(.link)
        .help("Open thread")
        .contextMenu {
            macBriefingRowMenu(for: row)
        }
    }

    @ViewBuilder
    private func macBriefingRowMenu(for row: MacBriefingRow) -> some View {
        Button("Open thread") {
            openMacBriefingRow(row)
        }
        Button("Mark done") {
            Task { await markMacBriefingRowDone(row) }
        }
        if row.source != .preparedAction {
            Menu("Snooze") {
                Button("Later today") {
                    let date = Calendar.current.date(byAdding: .hour, value: 4, to: Date()) ?? Date()
                    Task { await snoozeMacBriefingRow(row, until: date) }
                }
                Button("Tomorrow morning") {
                    let cal = Calendar.current
                    let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                    let date = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
                    Task { await snoozeMacBriefingRow(row, until: date) }
                }
                Button("Next week") {
                    let date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
                    Task { await snoozeMacBriefingRow(row, until: date) }
                }
            }
        }
        Divider()
        Button(row.source == .preparedAction ? "Not a draft I want" : "Not a reply", role: .destructive) {
            Task { await dismissMacBriefingRow(row) }
        }
    }

    private func openMacBriefingRow(_ row: MacBriefingRow) {
        if let id = row.threadId, !id.isEmpty, let openThread = onNavigateEmailThread {
            // Prefer the deep-link callback when wired so the user lands directly
            // on the thread instead of the inbox (matches iOS behavior).
            openThread(id)
        } else {
            // Fallback: when no thread-aware callback is wired or the row has no
            // threadId, route to the inbox so the row is never a silent no-op.
            onNavigate?(.email(.inbox))
        }
    }

    private func dismissMacBriefingRow(_ row: MacBriefingRow) async {
        switch row.source {
        case .openLoop:
            await services.emailService.dismissBriefingOpenLoop(id: row.backendId, threadId: row.threadId)
        case .preparedAction:
            await services.emailService.dismissBriefingPreparedAction(id: row.backendId, threadId: row.threadId)
        }
    }

    private func markMacBriefingRowDone(_ row: MacBriefingRow) async {
        switch row.source {
        case .openLoop:
            await services.emailService.completeBriefingOpenLoop(id: row.backendId, threadId: row.threadId)
        case .preparedAction:
            await services.emailService.dismissBriefingPreparedAction(id: row.backendId, threadId: row.threadId, feedback: "completed")
        }
    }

    private func snoozeMacBriefingRow(_ row: MacBriefingRow, until: Date) async {
        switch row.source {
        case .openLoop:
            await services.emailService.snoozeBriefingOpenLoop(id: row.backendId, threadId: row.threadId, until: until)
        case .preparedAction:
            await services.emailService.dismissBriefingPreparedAction(id: row.backendId, threadId: row.threadId, feedback: "helpful")
        }
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
                linkAction: { onNavigate?(.calendar(.all)) },
                addAction: { onNavigate?(.calendar(.all)) }
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
                let events = Array(todaysEvents.prefix(7).enumerated())
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(events, id: \.element.id) { index, event in
                            eventRow(event, index: index)
                            if index < events.count - 1 {
                                Divider().padding(.leading, MacTheme.spacing12)
                            }
                        }
                    }
                }
                .frame(maxHeight: 240)
                .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                        .stroke(MacTheme.cardBorder, lineWidth: 0.5)
                )
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHoveringEventIndex == index ? MacTheme.surfaceHover : Color.clear)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointerStyle(.link)
        .help("Show event details")
        .onHover { hovering in
            withAnimation(MacTheme.Motion.fast) {
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
                linkAction: { onNavigate?(.tasks) },
                addAction: { onNavigate?(.tasks) }
            )

            if orderedPreviewTasks.isEmpty {
                emptyActionCard(
                    message: "No open tasks — add one or sync from Reminders",
                    icon: "checkmark.circle",
                    actionTitle: "Go to Tasks",
                    action: { onNavigate?(.tasks) }
                )
            } else {
                let items = Array(orderedPreviewTasks.prefix(8).enumerated())
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(items, id: \.element.id) { index, task in
                            taskRow(task, index: index, dueCaption: taskDueCaption(task))
                            if index < items.count - 1 {
                                Divider().padding(.leading, MacTheme.spacing12)
                            }
                        }
                    }
                }
                .frame(maxHeight: 240)
                .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                        .stroke(MacTheme.cardBorder, lineWidth: 0.5)
                )
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
                let upcoming = Array(upcomingEvents.prefix(6).enumerated())
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(upcoming, id: \.element.id) { index, event in
                            upcomingEventRow(event, index: index)
                            if index < upcoming.count - 1 {
                                Divider().padding(.leading, MacTheme.spacing12)
                            }
                        }
                    }
                }
                .frame(maxHeight: 240)
                .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                        .stroke(MacTheme.cardBorder, lineWidth: 0.5)
                )
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
                    // All-day events were rendering as "Apr 30 at 00:00" — readers parse
                    // that as "midnight meeting" first, "all-day" never. Branch on the
                    // EKEvent flag and label them honestly.
                    if event.isAllDay {
                        Text("\(event.startDate.formatted(.dateTime.month(.abbreviated).day())) · All day")
                            .font(MacTheme.cardSubtitleFont())
                            .foregroundStyle(MacTheme.textSecondary)
                    } else {
                        Text(event.startDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(MacTheme.cardSubtitleFont())
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, MacTheme.spacing12)
            .padding(.vertical, MacTheme.spacing8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHoveringUpcomingEventIndex == index ? MacTheme.surfaceHover : Color.clear)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointerStyle(.link)
        .help("Show event details")
        .onHover { hovering in
            withAnimation(MacTheme.Motion.fast) {
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
            withAnimation(MacTheme.Motion.fast) {
                isHoveringMeetingIndex = hovering ? index : nil
            }
        }
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHoveringTaskIndex == index ? MacTheme.surfaceHover : Color.clear)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointerStyle(.link)
        .help("Edit task")
        .onHover { hovering in
            withAnimation(MacTheme.Motion.fast) {
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
                        guard !isConnectingGmail else { return }
                        isConnectingGmail = true
                        Task {
                            defer { isConnectingGmail = false }
                            await services.emailService.connectGmail(authService: services.authService)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if isConnectingGmail {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(.white)
                            } else {
                                Image(systemName: "link")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            Text(isConnectingGmail ? "Connecting…" : "Connect Gmail")
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
                    .disabled(isConnectingGmail)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, MacTheme.spacing20)
                .background(MacTheme.emptyStateSurface, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                        .stroke(MacTheme.cardBorder, lineWidth: 0.5)
                )
            } else if services.emailService.threads.isEmpty {
                if services.emailService.isLoadingThreads || services.emailService.isReconciling {
                    // Initial load or post-forceSync reconciliation — show the loading copy
                    // so a user with an empty backend DB doesn't see "No recent emails"
                    // mid-sync (~30s window while the workflow repopulates).
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
                let threads = Array(services.emailService.threads.prefix(5).enumerated())
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(threads, id: \.element.id) { index, thread in
                            emailCard(thread, index: index)
                            if index < threads.count - 1 {
                                Divider().padding(.horizontal, MacTheme.spacing12)
                            }
                        }
                    }
                }
                .frame(maxHeight: 240)
                .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                        .stroke(MacTheme.cardBorder, lineWidth: 0.5)
                )
            }
        }
    }

    private func emailCard(_ thread: EmailThread, index: Int) -> some View {
        Button {
            if let openThread = onNavigateEmailThread {
                openThread(thread.id)
            } else {
                onNavigate?(.email(.inbox))
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: MacTheme.spacing6) {
                    Text(thread.from.name)
                        .font(.system(size: 13, weight: thread.unread ? .semibold : .medium))
                        .foregroundStyle(MacTheme.textPrimary)
                        .lineLimit(1)

                    Circle()
                        .fill(thread.unread ? MacTheme.accent : Color.clear)
                        .frame(width: 6, height: 6)

                    Spacer(minLength: 0)

                    Text(emailTimeLabel(thread.date))
                        .font(MacTheme.metaFont())
                        .foregroundStyle(MacTheme.mutedText)
                }

                Text(thread.subject)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MacTheme.textPrimary.opacity(0.8))
                    .lineLimit(1)

                Text(thread.snippet)
                    .font(MacTheme.cardSubtitleFont())
                    .foregroundStyle(MacTheme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, MacTheme.spacing12)
            .padding(.vertical, MacTheme.spacing8)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(isHoveringEmailIndex == index ? MacTheme.surfaceHover : Color.clear)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointerStyle(.link)
        .help("Open thread: \(thread.subject)")
        .onHover { hovering in
            withAnimation(MacTheme.Motion.fast) {
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
        linkAction: (() -> Void)? = nil,
        addAction: (() -> Void)? = nil
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

                if let addAction {
                    Button(action: addAction) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MacTheme.textSecondary)
                            .frame(width: 24, height: 24)
                            .background(MacTheme.badgeSurface, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .pointerStyle(.link)
                    .help("Add new item")
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
                .padding(.horizontal, MacTheme.spacing12)
                .padding(.vertical, MacTheme.spacing4)
                .background(MacTheme.accent.opacity(0.08), in: Capsule(style: .continuous))
                .pointerStyle(.link)
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
            .pointerStyle(.link)
            .macClickablePointer()
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

    /// Relative time label matching iOS — "5m ago", "2h ago", "Yesterday", "Apr 23".
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

// MARK: - Hover row wrapper

/// Click-through row that yields a hover-state binding to its content builder.
/// Used by Today rows to reveal the inline action strip on pointer-over, in the
/// Things-3 / Mail.app style. Self-contained so each row owns its own hover
/// flag without polluting MacHomeView's @State surface.
private struct HoverableRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: (Bool) -> Content
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            content(isHovering)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovering ? MacTheme.surfaceHover : Color.clear)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

}

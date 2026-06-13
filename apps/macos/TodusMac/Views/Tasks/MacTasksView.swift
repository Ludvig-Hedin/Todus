import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// Tasks page — list view with search, sort, folder filter, and view mode toggle.
/// Desktop-optimized: denser rows, hover states, keyboard-friendly.
struct MacTasksView: View {
    @Environment(MacAppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]
    @Query(
        sort: [
            SortDescriptor(\FolderRecord.position, order: .forward),
            SortDescriptor(\FolderRecord.createdAt, order: .forward),
        ]
    )
    private var folders: [FolderRecord]

    @State private var searchText = ""
    /// Default to `.smart` (overdue → today → upcoming) so the user lands on
    /// "what should I do next" rather than "what did I create most recently".
    /// Persisted across launches via @AppStorage. (UX assessment QW2 + QW3.)
    @AppStorage("TaskApp.taskSortOrder") private var sortOrderRaw: String = TaskSortOrder.smart.rawValue
    private var sortOrder: TaskSortOrder {
        get { TaskSortOrder(rawValue: sortOrderRaw) ?? .smart }
    }
    @State private var selectedFolderID: UUID? = nil
    @AppStorage("TaskApp.selectedViewMode") private var viewModeRaw: String = TaskViewMode.list.rawValue
    private var viewMode: TaskViewMode {
        TaskViewMode(rawValue: viewModeRaw) ?? .list
    }
    @State private var selectedTask: TaskRecord? = nil
    @State private var visibleTasks: [TaskRecord] = []
    /// Smart-sort buckets — populated only when the active sort is `.smart`.
    /// Drives the section-headers list view so users see "Today / This week"
    /// structure rather than one long flat scroll. (UX assessment S1.)
    @State private var smartBuckets: [(bucket: TaskSmartSort.Bucket, tasks: [TaskRecord])] = []
    /// Completed within the last 24h — shown by default for quick undo.
    @State private var completedTasks: [TaskRecord] = []
    /// Completed more than 24h ago — folded behind a "Show older" link so
    /// finished work doesn't dominate the list. (UX assessment QW4.)
    @State private var olderCompletedTasks: [TaskRecord] = []
    @State private var showsOlderCompleted: Bool = false
    @State private var isConnectingReminders = false
    @State private var showRemindersConnected: Bool = false
    @State private var openingFolder: FolderRecord? = nil
    @State private var showFolderEditSheet: Bool = false
    /// Folder currently pending a delete-confirmation. Driving the
    /// `.confirmationDialog` off this optional gives us a typed handle to
    /// the folder being deleted, matching the row-level pattern.
    @State private var folderPendingDelete: FolderRecord? = nil
    /// Transient confirmation after restoring a completed task — without it
    /// the only feedback is the row silently vanishing from the Completed
    /// section, which reads as a bug rather than a successful action.
    @State private var restoreToast: MacToastMessage?
    @Namespace private var taskViewModeSegmentNamespace
    var onCreateItem: () -> Void

    var body: some View {
        // Split layout: task content on the left, detail panel inline on the right.
        // Matches MacEmailInboxView / MacMeetingsView pattern so users can keep
        // browsing the list while a task is open.
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Toolbar: view mode + search + sort
                toolbar
                    .padding(.bottom, MacTheme.spacing12)

                if showRemindersConnected {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.green)
                        Text("Apple Reminders connected.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MacTheme.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, MacTheme.spacing12)
                    .padding(.vertical, MacTheme.spacing8)
                    .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous)
                            .stroke(Color.green.opacity(0.25), lineWidth: 1)
                    )
                    .padding(.bottom, MacTheme.spacing12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Folder cards — horizontal scroller above the task list.
                // Tap a card to open the folder's mixed-type detail sheet.
                foldersRail
                    .padding(.bottom, MacTheme.spacing12)

                // Task list
                if visibleTasks.isEmpty && completedTasks.isEmpty {
                    emptyState
                } else {
                    taskContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let task = selectedTask {
                Divider()

                MacTaskDetailSheet(task: task, onClose: {
                    withAnimation(MacTheme.Motion.fast) {
                        selectedTask = nil
                    }
                })
                .id(task.id)
                // Compressible (was a hard 420) so opening a task can't force the
                // content wider than the window and shove the sidebar off-screen
                // when the AI panel is also open.
                .frame(minWidth: 300, idealWidth: 420, maxWidth: 460)
                .frame(maxHeight: .infinity)
                .background(MacTheme.contentBackground)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(MacTheme.Motion.fast, value: selectedTask?.id)
        .macToast($restoreToast)
        .onReceive(NotificationCenter.default.publisher(for: .todusTaskRescheduledByRecurrence)) { note in
            // MacTaskRow.toggleCompletion broadcasts this when a recurring
            // task's dueDate is bumped instead of being marked done. Surface
            // a toast so the user sees the reschedule (otherwise looks like
            // a tap-no-op since the row stays in the list).
            guard
                let info = note.userInfo,
                let title = info["title"] as? String,
                let nextDate = info["nextDueDate"] as? Date
            else { return }
            let formatted = nextDate.formatted(date: .abbreviated, time: .shortened)
            restoreToast = .success("'\(title)' rescheduled to \(formatted)")
        }
        .onAppear { recomputeTasks() }
        .task {
            do {
                try await services.syncSharedFolders(in: modelContext)
            } catch {
                AppLogger.shared.log("[MacTasksView] Failed to sync shared folders: \(error)")
            }
            await services.fetchFolderSummary(in: modelContext)
        }
        .onChange(of: allTasks) { recomputeTasks() }
        .onChange(of: searchText) { recomputeTasks() }
        .onChange(of: sortOrderRaw) { recomputeTasks() }
        .onChange(of: selectedFolderID) { recomputeTasks() }
        .sheet(item: $openingFolder) { folder in
            MacFolderDetailView(folder: folder)
        }
        .sheet(isPresented: $showFolderEditSheet) {
            MacFolderEditSheet(mode: .create)
        }
        .confirmationDialog(
            folderPendingDelete.map { "Delete \"\($0.name)\"?" } ?? "Delete folder?",
            isPresented: Binding(
                get: { folderPendingDelete != nil },
                set: { if !$0 { folderPendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: folderPendingDelete
        ) { folder in
            Button("Delete", role: .destructive) {
                Task { await services.deleteSharedFolder(folder, in: modelContext) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Items inside this folder will be unlinked but not deleted.")
        }
    }

    // MARK: - Folder Cards

    /// Horizontal rail of folder cards. Replaces the old capsule pill strip.
    private var foldersRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(folders) { folder in
                    Button {
                        openingFolder = folder
                    } label: {
                        MacFolderCardView(folder: folder, layout: .horizontal)
                    }
                    .buttonStyle(.plain)
                    .macClickablePointer()
                    .contextMenu {
                        Button("Open") { openingFolder = folder }
                        Button("Delete", role: .destructive) {
                            folderPendingDelete = folder
                        }
                    }
                }
                MacNewFolderCard(layout: .horizontal) {
                    showFolderEditSheet = true
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: MacTheme.spacing8) {
            // View mode picker
            viewModePicker

            if services.isSyncingSharedFolders {
                MacInlineRefreshBadge(label: "Syncing")
            }

            if !services.remindersSyncEnabled
                || services.remindersSyncService.authorizationState() != .authorized
            {
                connectRemindersButton
            }

            Button {
                onCreateItem()
            } label: {
                Label("Add Task", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                    .padding(.horizontal, MacTheme.spacing12)
                    .padding(.vertical, MacTheme.spacing6)
                    .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous)
                            .stroke(MacTheme.cardBorder, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .interactiveHitTarget(expansion: 6)
            .macClickablePointer()

            Spacer()

            // Search field
            HStack(spacing: MacTheme.spacing6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MacTheme.mutedText)

                TextField("Search tasks...", text: $searchText)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .frame(maxWidth: 200)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(MacTheme.mutedText)
                    }
                    .buttonStyle(.plain)
                    .interactiveHitTarget(expansion: 6)
                }
            }
            .padding(.horizontal, MacTheme.spacing8)
            .padding(.vertical, MacTheme.spacing6)
            .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )

            // Sort menu
            Menu {
                ForEach(TaskSortOrder.allCases) { order in
                    Button {
                        sortOrderRaw = order.rawValue
                    } label: {
                        Label(order.title, systemImage: sortOrder == order ? "checkmark" : order.systemImage)
                    }
                }
            } label: {
                HStack(spacing: MacTheme.spacing6) {
                    Text(sortOrder.title)
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(MacTheme.mutedText)
                .padding(.horizontal, MacTheme.spacing12)
                .padding(.vertical, MacTheme.spacing6)
                .background(
                    MacTheme.surfaceCard,
                    in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous)
                        .stroke(MacTheme.cardBorder, lineWidth: 0.5)
                )
            }
            .menuStyle(.borderlessButton)
            .interactiveHitTarget(expansion: 6)
            .tint(Color.primary.opacity(0.7))
            .macClickablePointer()
        }
    }

    private var connectRemindersButton: some View {
        Button {
            Task { await connectAppleReminders() }
        } label: {
            HStack(spacing: 6) {
                AppleRemindersIconView(size: 16)
                if isConnectingReminders {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 14, height: 14)
                }
                Text(isConnectingReminders ? "Connecting…" : "Connect Apple Reminders")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(MacTheme.textPrimary)
            .padding(.horizontal, MacTheme.spacing12)
            .padding(.vertical, MacTheme.spacing6)
            .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isConnectingReminders)
        .help("Sync tasks with Apple Reminders")
        .interactiveHitTarget(expansion: 6)
        .macClickablePointer()
    }

    private func connectAppleReminders() async {
        isConnectingReminders = true
        services.remindersSyncEnabled = true
        let granted = await services.requestRemindersPermissionIfNeeded()
        if granted {
            await services.importFromReminders(in: modelContext)
            services.syncExistingTasksToReminders(in: modelContext)
            // Show a brief confirmation banner so users know it worked —
            // the connect button just disappears otherwise, leaving no signal.
            withAnimation(MacTheme.Motion.base) {
                showRemindersConnected = true
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                withAnimation(MacTheme.Motion.base) {
                    showRemindersConnected = false
                }
            }
        } else {
            services.remindersSyncEnabled = false
        }
        isConnectingReminders = false
    }

    /// Same visual system as `CalendarViewModePicker` — strong selected pill on a recessed track.
    private var viewModePicker: some View {
        HStack(spacing: 2) {
            ForEach(TaskViewMode.allCases) { mode in
                let isSelected = viewMode == mode
                Button {
                    withAnimation(MacTheme.Motion.base) {
                        viewModeRaw = mode.rawValue
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        Text(mode.shortTitle)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .foregroundStyle(isSelected ? MacTheme.textPrimary : MacTheme.mutedText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        if isSelected {
                            Capsule(style: .continuous)
                                .fill(MacTheme.segmentedSelectedPill)
                                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                                .matchedGeometryEffect(id: "task-view-mode-pill", in: taskViewModeSegmentNamespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .interactiveHitTarget(expansion: 6)
                .macClickablePointer()
            }
        }
        .padding(3)
        .background(MacTheme.segmentedTrack, in: Capsule(style: .continuous))
    }

    // MARK: - Task Content

    private var taskContent: some View {
        Group {
            switch viewMode {
            case .list:
                listView
            case .board:
                boardView
            case .table:
                tableView
            case .calendar:
                datesView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - List View

    private var listView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MacTheme.spacing4) {
                if sortOrder == .smart && !smartBuckets.isEmpty {
                    ForEach(smartBuckets, id: \.bucket.id) { group in
                        bucketHeader(group.bucket, count: group.tasks.count)
                        ForEach(group.tasks) { task in
                            MacTaskRow(task: task, onSelect: { selectedTask = task })
                        }
                    }
                } else {
                    ForEach(visibleTasks) { task in
                        MacTaskRow(task: task, onSelect: { selectedTask = task })
                    }
                }

                if !completedTasks.isEmpty || !olderCompletedTasks.isEmpty {
                    completedSection
                }
            }
        }
    }

    /// Smart-sort bucket header — colour-coded so Overdue/Today catch the eye
    /// while Later/No-date stay visually quiet.
    @ViewBuilder
    private func bucketHeader(_ bucket: TaskSmartSort.Bucket, count: Int) -> some View {
        let tint = bucketTint(bucket)
        HStack(spacing: 8) {
            Image(systemName: bucket.systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(bucket.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MacTheme.textPrimary)
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(tint.opacity(0.12), in: Capsule())
                }
                Text(bucket.subtitle)
                    .font(MacTheme.cardSubtitleFont())
                    .foregroundStyle(MacTheme.mutedText)
            }
            Spacer()
        }
        .padding(.top, MacTheme.spacing12)
        .padding(.bottom, MacTheme.spacing4)
    }

    private func bucketTint(_ bucket: TaskSmartSort.Bucket) -> Color {
        switch bucket {
        case .overdue: return Color(red: 0.85, green: 0.30, blue: 0.25)
        case .today: return Color(red: 0.88, green: 0.55, blue: 0.20)
        case .thisWeek: return Color(red: 0.40, green: 0.56, blue: 0.85)
        case .later: return MacTheme.mutedText
        case .noDate: return MacTheme.mutedText.opacity(0.85)
        }
    }

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing4) {
            HStack {
                Text("COMPLETED")
                    .font(MacTheme.sectionHeaderFont())
                    .foregroundStyle(MacTheme.mutedText)
                    .tracking(0.8)
                Spacer()
                Text("\(showsOlderCompleted ? completedTasks.count + olderCompletedTasks.count : completedTasks.count)")
                    .font(MacTheme.metaFont())
                    .foregroundStyle(MacTheme.mutedText)
            }
            .padding(.top, MacTheme.spacing16)
            .padding(.bottom, MacTheme.spacing4)

            let visibleCompleted = showsOlderCompleted
                ? completedTasks + olderCompletedTasks
                : completedTasks

            ForEach(visibleCompleted) { task in
                HStack(spacing: MacTheme.spacing8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(MacTheme.mutedText)
                    Text(task.title)
                        .font(MacTheme.cardTitleFont())
                        .foregroundStyle(MacTheme.mutedText)
                        .strikethrough()
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText.opacity(0.5))
                        // Hover tooltip clarifies that the small icon is
                        // tappable — it's a passive glyph otherwise.
                        .help("Restore task")
                }
                .padding(.horizontal, MacTheme.spacing12)
                .padding(.vertical, MacTheme.spacing6)
                .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
                .contentShape(Rectangle())
                .macClickablePointer()
                .help("Click to restore")
                .onTapGesture {
                    let restoredTitle = task.title
                    withAnimation(MacTheme.Motion.base) {
                        task.status = .todo
                        task.completed = false
                        task.updatedAt = .now
                        task.syncState = .pendingUpload
                    }
                    try? modelContext.save()
                    recomputeTasks()
                    // Confirm the row was restored — the row disappearing from
                    // the Completed section alone isn't a clear "I did it" signal.
                    restoreToast = .success("Restored ‘\(restoredTitle)’")
                }
            }

            if !olderCompletedTasks.isEmpty {
                Button {
                    withAnimation(MacTheme.Motion.base) {
                        showsOlderCompleted.toggle()
                    }
                } label: {
                    Text(showsOlderCompleted
                         ? "Hide older"
                         : "Show \(olderCompletedTasks.count) older completed")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MacTheme.mutedText)
                        .padding(.top, MacTheme.spacing4)
                }
                .buttonStyle(.plain)
                .macClickablePointer()
            }
        }
    }

    // MARK: - Board View (Kanban)

    private var boardView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: MacTheme.spacing12) {
                ForEach(TaskStatus.allCases) { status in
                    MacBoardColumn(
                        status: status,
                        tasks: visibleTasks.filter { $0.status == status },
                        onSelect: { selectedTask = $0 },
                        onSetStatus: { task, newStatus in
                            applyTaskStatusOnBoard(task, to: newStatus)
                        }
                    )
                }
            }
            .padding(.trailing, MacTheme.spacing4)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func applyTaskStatusOnBoard(_ task: TaskRecord, to status: TaskStatus) {
        guard task.status != status else { return }
        withAnimation(MacTheme.Motion.fast) {
            task.status = status
            task.updatedAt = .now
            task.syncState = .pendingUpload
            try? modelContext.save()
        }
        recomputeTasks()
    }

    // MARK: - Table View

    private var tableView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Table header
                HStack(spacing: 0) {
                    Text("Task")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Status")
                        .frame(width: 80, alignment: .leading)
                    Text("Priority")
                        .frame(width: 80, alignment: .leading)
                    Text("Due Date")
                        .frame(width: 120, alignment: .leading)
                    Text("Folder")
                        .frame(width: 100, alignment: .leading)
                }
                .font(MacTheme.sectionHeaderFont())
                .foregroundStyle(MacTheme.mutedText)
                .tracking(0.5)
                .padding(.horizontal, MacTheme.spacing12)
                .padding(.vertical, MacTheme.spacing8)

                Divider().opacity(0.3)

                LazyVStack(spacing: 0) {
                    ForEach(visibleTasks) { task in
                        tableRow(task)
                        Divider().opacity(0.15)
                    }
                }
            }
            .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Dates View (Kanban by due-date bucket)

    private struct DateBucket: Identifiable {
        let id: String
        let label: String
        let subtitle: String
        let icon: String
        let tint: Color
        let tasks: [TaskRecord]
    }

    private var dateBuckets: [DateBucket] {
        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        guard let tomorrowStart = cal.date(byAdding: .day, value: 1, to: todayStart),
              let weekEnd = cal.date(byAdding: .day, value: 7, to: todayStart) else { return [] }

        var overdue: [TaskRecord] = []
        var today: [TaskRecord] = []
        var tomorrow: [TaskRecord] = []
        var thisWeek: [TaskRecord] = []
        var later: [TaskRecord] = []
        var noDate: [TaskRecord] = []

        for task in visibleTasks {
            guard let due = task.dueDate else { noDate.append(task); continue }
            let dueDay = cal.startOfDay(for: due)
            if dueDay < todayStart { overdue.append(task) }
            else if dueDay == todayStart { today.append(task) }
            else if dueDay == tomorrowStart { tomorrow.append(task) }
            else if dueDay < weekEnd { thisWeek.append(task) }
            else { later.append(task) }
        }

        var result: [DateBucket] = []
        if !overdue.isEmpty {
            result.append(DateBucket(
                id: "overdue", label: "Overdue", subtitle: "Past due",
                icon: "exclamationmark.circle.fill", tint: Color(red: 0.85, green: 0.25, blue: 0.20),
                tasks: overdue
            ))
        }
        if !today.isEmpty {
            result.append(DateBucket(
                id: "today", label: "Today", subtitle: "Needs attention first",
                icon: "sun.max.fill", tint: Color(red: 0.88, green: 0.50, blue: 0.20), tasks: today
            ))
        }
        if !tomorrow.isEmpty {
            result.append(DateBucket(
                id: "tomorrow", label: "Tomorrow", subtitle: "Coming up next",
                icon: "sunrise.fill", tint: Color(red: 0.75, green: 0.62, blue: 0.30), tasks: tomorrow
            ))
        }
        if !thisWeek.isEmpty {
            result.append(DateBucket(
                id: "week", label: "This Week", subtitle: "Plan the week ahead",
                icon: "calendar", tint: Color(red: 0.40, green: 0.56, blue: 0.85), tasks: thisWeek
            ))
        }
        if !later.isEmpty {
            result.append(DateBucket(
                id: "later", label: "Later", subtitle: "Longer-term work",
                icon: "calendar.badge.clock", tint: Color(red: 0.55, green: 0.55, blue: 0.60), tasks: later
            ))
        }
        if !noDate.isEmpty {
            result.append(DateBucket(
                id: "nodate", label: "No Date", subtitle: "Needs a planned time",
                icon: "calendar.badge.minus", tint: Color(red: 0.50, green: 0.50, blue: 0.52), tasks: noDate
            ))
        }
        return result
    }

    private var datesView: some View {
        Group {
            if dateBuckets.isEmpty {
                VStack(spacing: MacTheme.spacing12) {
                    Spacer()
                    Image(systemName: searchText.isEmpty ? "calendar.badge.clock" : "magnifyingglass")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(MacTheme.mutedText.opacity(0.5))
                    Text(searchText.isEmpty ? "No upcoming tasks" : "No matching tasks")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(MacTheme.textSecondary)
                    Text(searchText.isEmpty ? "Tasks with due dates will be grouped here by date." : "Try a different search term.")
                        .font(MacTheme.cardSubtitleFont())
                        .foregroundStyle(MacTheme.mutedText)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: MacTheme.spacing16) {
                        ForEach(dateBuckets) { bucket in
                            VStack(alignment: .leading, spacing: MacTheme.spacing8) {
                                HStack(alignment: .firstTextBaseline, spacing: MacTheme.spacing8) {
                                    Image(systemName: bucket.icon)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(bucket.tint)
                                    Text(bucket.label)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(MacTheme.textPrimary)
                                    Text(bucket.subtitle)
                                        .font(MacTheme.cardSubtitleFont())
                                        .foregroundStyle(MacTheme.mutedText)
                                    Spacer()
                                    Text("\(bucket.tasks.count)")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(bucket.tint)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(bucket.tint.opacity(0.10), in: Capsule())
                                }

                                VStack(spacing: MacTheme.spacing4) {
                                    ForEach(bucket.tasks) { task in
                                        MacTaskRow(task: task, onSelect: { selectedTask = task })
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Table View helpers

    @State private var hoveringTableRow: UUID? = nil

    private func tableRow(_ task: TaskRecord) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: MacTheme.spacing6) {
                Image(systemName: task.status.systemImage)
                    .font(.system(size: 11))
                    .foregroundStyle(task.status.tintColor)
                Text(task.title)
                    .font(MacTheme.cardTitleFont())
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(task.status.title)
                .font(MacTheme.cardSubtitleFont())
                .foregroundStyle(task.status.tintColor)
                .frame(width: 80, alignment: .leading)

            Text(task.priority == .none ? "—" : task.priority.title)
                .font(MacTheme.cardSubtitleFont())
                .foregroundStyle(task.priority == .none ? MacTheme.mutedText : priorityColor(task.priority))
                .frame(width: 80, alignment: .leading)

            Text(task.dueDate != nil ? TaskDateFormatter.shortDate.string(from: task.dueDate!) : "—")
                .font(MacTheme.cardSubtitleFont())
                .foregroundStyle(task.dueDate != nil ? dueDateColor(task.dueDate!) : MacTheme.mutedText)
                .frame(width: 120, alignment: .leading)

            Text(task.folder?.name ?? "—")
                .font(MacTheme.cardSubtitleFont())
                .foregroundStyle(MacTheme.mutedText)
                .frame(width: 100, alignment: .leading)
        }
        .padding(.horizontal, MacTheme.spacing12)
        .padding(.vertical, MacTheme.spacing6)
        .background(hoveringTableRow == task.id ? MacTheme.surfaceHover : Color.clear)
        .contentShape(Rectangle())
        .macClickablePointer()
        .onTapGesture { selectedTask = task }
        .onHover { hovering in
            hoveringTableRow = hovering ? task.id : nil
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: MacTheme.spacing12) {
            Spacer()
            Image(systemName: searchText.isEmpty ? "checkmark.circle" : "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(MacTheme.mutedText.opacity(0.5))

            Text(searchText.isEmpty ? "No tasks yet" : "No matching tasks")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(MacTheme.textSecondary)

            Text(searchText.isEmpty ? "Use Add Task to capture something new right from this page." : "Try a different search term.")
                .font(MacTheme.cardSubtitleFont())
                .foregroundStyle(MacTheme.mutedText)

            // Surface the empty-state action as a real button, not a hyperlink-styled
            // text. The previous plain text + accent color easily read as a footer
            // link rather than the primary call to action.
            Button {
                if searchText.isEmpty {
                    onCreateItem()
                } else {
                    searchText = ""
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: searchText.isEmpty ? "plus" : "xmark")
                        .font(.system(size: 11, weight: .bold))
                    Text(searchText.isEmpty ? "Add Task" : "Clear search")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(MacTheme.primaryButtonForeground)
                .padding(.horizontal, MacTheme.spacing16)
                .padding(.vertical, MacTheme.spacing8)
                .background(MacTheme.accent, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .interactiveHitTarget(expansion: 6)
            .macClickablePointer()
            .padding(.top, MacTheme.spacing4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func recomputeTasks() {
        let activeTasks = allTasks.filter { task in
            task.status != .done &&
            (selectedFolderID == nil || task.folderID == selectedFolderID) &&
            matchesSearch(task)
        }
        visibleTasks = sorted(activeTasks)
        smartBuckets = sortOrder == .smart ? TaskSmartSort.bucketed(activeTasks) : []
        var done = allTasks.filter { task in
            task.status == .done &&
            (selectedFolderID == nil || task.folderID == selectedFolderID) &&
            matchesSearch(task)
        }
        done.sort { $0.updatedAt > $1.updatedAt }
        // Split completed into "recent (≤24h)" vs "older" so the list doesn't
        // get dominated by yesterday's wins. (UX assessment QW4.)
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        completedTasks = done.filter { $0.updatedAt >= cutoff }
        olderCompletedTasks = done.filter { $0.updatedAt < cutoff }
    }

    private func matchesSearch(_ task: TaskRecord) -> Bool {
        guard !searchText.isEmpty else { return true }
        return task.title.localizedCaseInsensitiveContains(searchText) ||
               task.taskDescription.localizedCaseInsensitiveContains(searchText)
    }

    private func sorted(_ tasks: [TaskRecord]) -> [TaskRecord] {
        switch sortOrder {
        case .smart:        return TaskSmartSort.sorted(tasks)
        case .newest:       return tasks.sorted { $0.createdAt > $1.createdAt }
        case .oldest:       return tasks.sorted { $0.createdAt < $1.createdAt }
        case .alphabetical: return tasks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .dueDate:
            return tasks.sorted {
                switch ($0.dueDate, $1.dueDate) {
                case let (a?, b?): return a < b
                case (nil, nil): return $0.createdAt > $1.createdAt
                case (nil, _): return false
                case (_, nil): return true
                }
            }
        }
    }

    private func dueDateColor(_ date: Date) -> Color {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return Color(red: 0.88, green: 0.65, blue: 0.20) }
        if date < Date() { return Color(red: 0.85, green: 0.30, blue: 0.25) }
        return MacTheme.textSecondary
    }

    private func priorityColor(_ priority: AppTaskPriority) -> Color {
        switch priority {
        case .high:   return Color(red: 0.85, green: 0.30, blue: 0.25)
        case .medium: return Color(red: 0.88, green: 0.65, blue: 0.20)
        case .low:    return Color(red: 0.50, green: 0.60, blue: 0.70)
        default:      return MacTheme.mutedText
        }
    }
}

// MARK: - Board column (drag & drop between stages)

private struct MacBoardColumn: View {
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]

    let status: TaskStatus
    let tasks: [TaskRecord]
    let onSelect: (TaskRecord) -> Void
    let onSetStatus: (TaskRecord, TaskStatus) -> Void

    @State private var isDropTargeted = false

    private let columnWidth: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing8) {
            HStack(spacing: MacTheme.spacing6) {
                Image(systemName: status.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(status.tintColor)

                Text(status.title.uppercased())
                    .font(MacTheme.sectionHeaderFont())
                    .foregroundStyle(MacTheme.mutedText)
                    .tracking(0.8)

                if !tasks.isEmpty {
                    Text("\(tasks.count)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(MacTheme.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(MacTheme.badgeSurface, in: RoundedRectangle(cornerRadius: MacTheme.pillRadius))
                }

                Spacer()
            }
            .padding(.bottom, MacTheme.spacing4)

            ScrollView {
                LazyVStack(spacing: MacTheme.spacing4) {
                    if tasks.isEmpty {
                        macBoardEmptyColumnHint
                    } else {
                        ForEach(tasks) { task in
                            MacTaskRow(task: task, onSelect: { onSelect(task) }, allowsDrag: true)
                        }
                    }
                }
            }
        }
        .frame(width: columnWidth, alignment: .topLeading)
        .padding(MacTheme.spacing12)
        .background(
            isDropTargeted ? status.tintColor.opacity(0.06) : MacTheme.emptyStateSurface,
            in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(isDropTargeted ? status.tintColor.opacity(0.22) : MacTheme.cardBorder, lineWidth: isDropTargeted ? 1 : 0.5)
        )
        .dropDestination(for: String.self, action: handleDrop, isTargeted: { targeted in
            withAnimation(MacTheme.Motion.fast) { isDropTargeted = targeted }
        })
        .contentShape(Rectangle())
    }

    private var macBoardEmptyColumnHint: some View {
        Text("Drop a task here")
            .font(MacTheme.cardSubtitleFont())
            .foregroundStyle(MacTheme.mutedText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, MacTheme.spacing12)
    }

    private func handleDrop(items: [String], location _: CGPoint) -> Bool {
        for item in items {
            guard let id = UUID(uuidString: item),
                  let task = allTasks.first(where: { $0.id == id }) else { continue }
            onSetStatus(task, status)
        }
        isDropTargeted = false
        return true
    }
}

// MARK: - Task Row Component

/// A single task row for the list and board views — desktop-optimized with hover states.
struct MacTaskRow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(MacAppServices.self) private var services
    let task: TaskRecord
    let onSelect: () -> Void
    /// When true, the row participates in board drag-and-drop between columns.
    var allowsDrag: Bool = false

    @State private var isHovered = false
    @State private var showDeleteConfirm = false

    var body: some View {
        Group {
            if allowsDrag {
                rowButton
                    .draggable(task.id.uuidString)
            } else {
                rowButton
            }
        }
        .contextMenu {
            Button("Open") { onSelect() }
                .keyboardShortcut(.return, modifiers: [])

            Button(task.completed ? "Mark as incomplete" : "Mark complete") {
                toggleCompletion()
            }
            .keyboardShortcut("d", modifiers: .command)

            Divider()

            Button {
                Self.copyToPasteboard(task.title)
            } label: {
                Label("Copy title", systemImage: "doc.on.doc")
            }
            if !task.taskDescription.isEmpty && task.taskDescription != task.title {
                Button {
                    Self.copyToPasteboard(task.taskDescription)
                } label: {
                    Label("Copy description", systemImage: "text.quote")
                }
            }
            Button {
                let box = task.completed ? "- [x]" : "- [ ]"
                let md: String
                if !task.taskDescription.isEmpty && task.taskDescription != task.title {
                    md = "\(box) \(task.title)\n  \(task.taskDescription)"
                } else {
                    md = "\(box) \(task.title)"
                }
                Self.copyToPasteboard(md)
            } label: {
                Label("Copy as Markdown", systemImage: "checkmark.square")
            }

            Button {
                duplicateTask()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }

            Menu("Priority") {
                ForEach(AppTaskPriority.allCases) { p in
                    Button {
                        guard p != task.priority else { return }
                        withAnimation(MacTheme.Motion.base) {
                            task.priority = p
                            task.updatedAt = .now
                            task.syncState = .pendingUpload
                            try? modelContext.save()
                        }
                    } label: {
                        if p == task.priority {
                            Label(p.title, systemImage: "checkmark")
                        } else {
                            Text(p.title)
                        }
                    }
                }
            }

            Divider()

            // Snooze sub-menu — macOS task row didn't have one.
            // Snooze should be as cheap as Complete or Delete on a busy day.
            // (UX assessment S6.)
            Menu("Snooze") {
                ForEach(SnoozeOption.allCases, id: \.self) { option in
                    Button(option.label) {
                        snooze(to: option.date())
                    }
                }
            }

            Divider()

            Button("Delete", role: .destructive) {
                showDeleteConfirm = true
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }
        .confirmationDialog(
            "Delete \"\(task.title)\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                performDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This task will be removed from Todus and unlinked from Apple Reminders if connected.")
        }
    }

    /// Mirrors deletion across the local store, the backend (`tasks.sync`),
    /// and Apple Reminders so the task disappears everywhere instead of
    /// coming back on the next sync.
    private func performDelete() {
        let id = task.id
        // Snapshot the AppleRemindersSyncService delete before we drop the
        // SwiftData object — that call needs the live `reminderIdentifier`.
        if task.reminderIdentifier != nil {
            services.remindersSyncService.delete(task)
        }
        modelContext.delete(task)
        try? modelContext.save()
        Task {
            await services.taskSyncService.enqueueDelete(taskID: id, in: modelContext)
        }
    }

    private func snooze(to date: Date) {
        withAnimation(MacTheme.Motion.base) {
            task.dueDate = date
            task.updatedAt = .now
            task.syncState = .pendingUpload
            try? modelContext.save()
        }
    }

    /// Centralised pasteboard write — clears prior contents so older type
    /// payloads (RTF, file URL) can't shadow the plain-text Copy we just
    /// performed when the user pastes into another app.
    fileprivate static func copyToPasteboard(_ value: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(value, forType: .string)
    }

    /// Creates a new TaskRecord with the same title/description/status/folder/priority
    /// as the source. The new task gets a fresh UUID and createdAt so it appears
    /// at the top of the smart-sort buckets — same behaviour the user expects
    /// from "Duplicate" in Apple Reminders / Notion.
    private func duplicateTask() {
        let copy = TaskRecord(
            rawInput: task.rawInput,
            title: task.title,
            taskDescription: task.taskDescription,
            completed: false,
            status: task.status,
            priority: task.priority,
            attachmentNames: [],
            reminderIdentifier: nil,
            createdAt: .now,
            updatedAt: .now,
            dueDate: task.dueDate,
            folder: task.folder,
            parseState: .parsed,
            syncState: .pendingUpload
        )
        modelContext.insert(copy)
        do { try modelContext.save() } catch {
            AppLogger.shared.log("MacTaskRow.duplicateTask save failed: \(error.localizedDescription)")
        }
        Task { await services.taskSyncService.enqueueUpsert(copy, in: modelContext) }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func toggleCompletion() {
        // If a recurring task is being marked done, advance its due date to the
        // next occurrence instead of completing it outright. Matches the iOS
        // behavior where recurrence keeps the task alive until the rule ends.
        if !task.completed, let rule = task.recurrenceRule, !rule.isEmpty {
            if let due = task.dueDate, let next = nextRecurrence(after: due, rule: rule) {
                let title = task.title
                withAnimation(MacTheme.Motion.base) {
                    task.dueDate = next
                    task.updatedAt = .now
                    task.syncState = .pendingUpload
                    try? modelContext.save()
                }
                // Visible feedback: a recurring "complete" tap looks identical
                // to a non-op without any cue. Haptic + a NotificationCenter
                // post let the parent surface a toast like "Rescheduled to …".
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                NotificationCenter.default.post(
                    name: .todusTaskRescheduledByRecurrence,
                    object: nil,
                    userInfo: [
                        "title": title,
                        "nextDueDate": next
                    ]
                )
                return
            } else if task.dueDate == nil {
                AppLogger.shared.log("[Tasks] recurrence rule '\(rule)' has no dueDate — completing as one-off")
            } else {
                AppLogger.shared.log("[Tasks] recurrence rule '\(rule)' not supported by nextRecurrence — completing as one-off")
            }
        }

        withAnimation(MacTheme.Motion.base) {
            let nextStatus: TaskStatus = task.completed ? .todo : .done
            task.status = nextStatus
            task.completed = (nextStatus == .done)
            task.updatedAt = .now
            task.syncState = .pendingUpload
            try? modelContext.save()
        }
    }

    @ViewBuilder
    private var rowButton: some View {
        Button(action: onSelect) {
            HStack(spacing: MacTheme.spacing8) {
                Image(systemName: task.status.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(task.completed ? MacTheme.mutedText : task.status.tintColor)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(task.title)
                            .font(MacTheme.cardTitleFont())
                            .foregroundStyle(task.completed ? MacTheme.mutedText : MacTheme.textPrimary)
                            .strikethrough(task.completed)
                            .lineLimit(1)

                        // Parsing indicator — was previously an unlabelled sparkle.
                        // Adding "Parsing…" copy makes the AI behaviour explicit so
                        // users don't mistake it for a favourite/star affordance.
                        // (UX assessment QW5.)
                        if task.parseState == .pending {
                            HStack(spacing: 3) {
                                Image(systemName: "sparkle")
                                    .font(.system(size: 9, weight: .semibold))
                                    .symbolEffect(.pulse.wholeSymbol, options: .repeating)
                                Text("Parsing…")
                                    .font(.system(size: 10, weight: .semibold))
                                    .tracking(-0.1)
                            }
                            .foregroundStyle(MacTheme.mutedText)
                        }
                    }

                    // Metadata row — email origin first, then date/priority/folder.
                    // Showing origin rebuilds trust in AI-extracted tasks: users
                    // can verify "this came from a real thread" before acting.
                    // (UX assessment QW6.)
                    HStack(spacing: MacTheme.spacing4) {
                        if task.emailThreadId != nil {
                            metaTag(text: "Email", icon: "envelope.fill",
                                    color: Color(red: 0.35, green: 0.55, blue: 0.85))
                        }
                        if let dueDate = task.dueDate {
                            metaTag(
                                text: TaskDateFormatter.shortDate.string(from: dueDate),
                                icon: "calendar",
                                color: dueDateColor(dueDate)
                            )
                        }
                        if task.priority != .none {
                            metaTag(text: task.priority.title, icon: "flag.fill", color: priorityColor(task.priority))
                        }
                        if let folder = task.folder {
                            metaTag(text: folder.name, icon: "folder", color: MacTheme.mutedText.opacity(0.9))
                        }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MacTheme.mutedText.opacity(isHovered ? 0.9 : 0.45))
            }
            .padding(.horizontal, MacTheme.spacing12)
            .padding(.vertical, MacTheme.spacing8)
            .background(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .fill(isHovered ? MacTheme.surfaceHover : MacTheme.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .macClickablePointer()
    }

    private func metaTag(text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: MacTheme.pillRadius))
    }

    private func dueDateColor(_ date: Date) -> Color {
        if Calendar.current.isDateInToday(date) { return Color(red: 0.88, green: 0.65, blue: 0.20) }
        if date < Date() { return Color(red: 0.85, green: 0.30, blue: 0.25) }
        return MacTheme.mutedText
    }

    private func priorityColor(_ priority: AppTaskPriority) -> Color {
        switch priority {
        case .high:   return Color(red: 0.85, green: 0.30, blue: 0.25)
        case .medium: return Color(red: 0.88, green: 0.65, blue: 0.20)
        case .low:    return Color(red: 0.50, green: 0.60, blue: 0.70)
        default:      return MacTheme.mutedText
        }
    }
}

// MARK: - Task Detail Sheet

/// Task detail sheet for viewing/editing a single task on macOS.
struct MacTaskDetailSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FolderRecord.name) private var folders: [FolderRecord]
    let task: TaskRecord
    /// Optional close handler. When provided (inline split-panel mode) the header
    /// shows a close button. When nil, falls back to environment dismiss for legacy sheet usage.
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var editedTitle: String = ""
    @State private var editedDescription: String = ""
    @State private var editedStatus: TaskStatus = .todo
    @State private var editedPriority: AppTaskPriority = .none
    @State private var editedDueDate: Date? = nil
    @State private var hasDueDate = false
    @State private var selectedFolderID: UUID? = nil

    /// Lightweight option for the recurrence picker. `none` means non-recurring.
    /// Raw values match the iOS keyword shape stored in `TaskRecord.recurrenceRule`.
    private enum RecurrenceOption: String, CaseIterable, Identifiable {
        case none
        case daily
        case weekly
        case monthly
        case yearly

        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: return "None"
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            case .monthly: return "Monthly"
            case .yearly: return "Yearly"
            }
        }

        /// Decode a stored `recurrenceRule` string into one of the simple
        /// keyword options. RRULE strings (FREQ=DAILY etc) are matched
        /// lossily so iOS-created tasks render sensibly on macOS.
        static func from(rule: String?) -> RecurrenceOption {
            guard let rule = rule?.trimmingCharacters(in: .whitespacesAndNewlines), !rule.isEmpty else {
                return .none
            }
            let lower = rule.lowercased()
            if lower == "daily" || lower.contains("freq=daily") { return .daily }
            if lower == "weekly" || lower.contains("freq=weekly") { return .weekly }
            if lower == "monthly" || lower.contains("freq=monthly") { return .monthly }
            if lower == "yearly" || lower.contains("freq=yearly") { return .yearly }
            return .none
        }

        /// Stored representation. `none` writes `nil` to clear the column.
        var storedValue: String? {
            self == .none ? nil : rawValue
        }
    }

    @State private var recurrence: RecurrenceOption = .none
    @State private var checklistItems: [ChecklistItem] = []
    @State private var attachmentPaths: [String] = []

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: MacTheme.spacing8) {
                if onClose != nil {
                    Button {
                        close()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MacTheme.mutedText)
                            .frame(width: 22, height: 22)
                            .background(MacTheme.surfaceCard, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .interactiveHitTarget(expansion: 4)
                    .help("Close")
                }
                Text("Task Details")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Spacer()
                Button("Save") {
                    saveChanges()
                    close()
                }
                .font(.system(size: 13, weight: .medium))
                .macClickablePointer()
                // Disable Save when the drafts match the task — saves a write,
                // and makes it obvious to the user there's nothing pending.
                .disabled(!hasUnsavedChanges)
            }
            .padding(MacTheme.spacing16)

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: MacTheme.spacing16) {
                    // Title
                    VStack(alignment: .leading, spacing: MacTheme.spacing4) {
                        Text("TITLE")
                            .font(MacTheme.sectionHeaderFont())
                            .foregroundStyle(MacTheme.mutedText)
                            .tracking(0.8)
                        TextField("Task title", text: $editedTitle)
                            .font(.system(size: 14))
                            .textFieldStyle(.plain)
                            .padding(MacTheme.spacing8)
                            .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius))
                            .overlay(RoundedRectangle(cornerRadius: MacTheme.buttonRadius).stroke(MacTheme.cardBorder, lineWidth: 0.5))
                    }

                    // Description
                    VStack(alignment: .leading, spacing: MacTheme.spacing4) {
                        Text("DESCRIPTION")
                            .font(MacTheme.sectionHeaderFont())
                            .foregroundStyle(MacTheme.mutedText)
                            .tracking(0.8)
                        TextEditor(text: $editedDescription)
                            .font(.system(size: 13))
                            .frame(minHeight: 60)
                            .padding(MacTheme.spacing4)
                            .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius))
                            .overlay(RoundedRectangle(cornerRadius: MacTheme.buttonRadius).stroke(MacTheme.cardBorder, lineWidth: 0.5))
                            .scrollContentBackground(.hidden)
                    }

                    // Status + Priority row
                    HStack(spacing: MacTheme.spacing16) {
                        VStack(alignment: .leading, spacing: MacTheme.spacing4) {
                            Text("STATUS")
                                .font(MacTheme.sectionHeaderFont())
                                .foregroundStyle(MacTheme.mutedText)
                                .tracking(0.8)
                            Picker("Status", selection: $editedStatus) {
                                ForEach(TaskStatus.allCases) { s in
                                    Text(s.title).tag(s)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        VStack(alignment: .leading, spacing: MacTheme.spacing4) {
                            Text("PRIORITY")
                                .font(MacTheme.sectionHeaderFont())
                                .foregroundStyle(MacTheme.mutedText)
                                .tracking(0.8)
                            Picker("Priority", selection: $editedPriority) {
                                ForEach(AppTaskPriority.allCases) { p in
                                    Text(p.title).tag(p)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }

                    // Due date
                    VStack(alignment: .leading, spacing: MacTheme.spacing4) {
                        HStack {
                            Text("DUE DATE")
                                .font(MacTheme.sectionHeaderFont())
                                .foregroundStyle(MacTheme.mutedText)
                                .tracking(0.8)
                            Spacer()
                            Toggle("", isOn: $hasDueDate)
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .tint(MacTheme.switchTint)
                        }
                        if hasDueDate {
                            DatePicker("", selection: Binding(
                                get: { editedDueDate ?? Date() },
                                set: { editedDueDate = $0 }
                            ))
                            .labelsHidden()
                            .datePickerStyle(.field)
                        }
                    }

                    VStack(alignment: .leading, spacing: MacTheme.spacing4) {
                        Text("FOLDER")
                            .font(MacTheme.sectionHeaderFont())
                            .foregroundStyle(MacTheme.mutedText)
                            .tracking(0.8)
                        Picker("Folder", selection: Binding(
                            get: { selectedFolderID?.uuidString ?? "" },
                            set: { selectedFolderID = UUID(uuidString: $0) }
                        )) {
                            Text("Inbox").tag("")
                            ForEach(folders) { folder in
                                Text(folder.name).tag(folder.id.uuidString)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    recurrenceSection
                    checklistSection
                    attachmentsSection

                    HStack(spacing: MacTheme.spacing6) {
                        Text("Created")
                            .font(MacTheme.cardSubtitleFont())
                            .foregroundStyle(MacTheme.mutedText)
                        Text(task.createdAt, format: .dateTime.month().day().year().hour().minute())
                            .font(MacTheme.cardSubtitleFont())
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                }
                .padding(MacTheme.spacing16)
            }
        }
        .onAppear {
            editedTitle = task.title
            editedDescription = task.taskDescription
            editedStatus = task.status
            editedPriority = task.priority
            editedDueDate = task.dueDate
            hasDueDate = task.dueDate != nil
            selectedFolderID = task.folderID
            recurrence = RecurrenceOption.from(rule: task.recurrenceRule)
            checklistItems = task.checklistItems.sorted { $0.order < $1.order }
            attachmentPaths = task.attachmentPaths
        }
    }

    // MARK: - Recurrence

    private var recurrenceSection: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing4) {
            Text("RECURRENCE")
                .font(MacTheme.sectionHeaderFont())
                .foregroundStyle(MacTheme.mutedText)
                .tracking(0.8)
            Picker("Recurrence", selection: $recurrence) {
                ForEach(RecurrenceOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            // Inline preview of the next occurrence so users can verify the
            // rule resolves to a real date before saving.
            if recurrence != .none {
                if let due = editedDueDate,
                   let rule = recurrence.storedValue,
                   let next = nextRecurrence(after: due, rule: rule) {
                    Text("Next: \(next.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.mutedText)
                } else {
                    Text("Set a due date to enable recurrence.")
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.mutedText)
                }
            }
        }
    }

    // MARK: - Checklist

    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing8) {
            Text("CHECKLIST")
                .font(MacTheme.sectionHeaderFont())
                .foregroundStyle(MacTheme.mutedText)
                .tracking(0.8)

            VStack(spacing: MacTheme.spacing6) {
                ForEach($checklistItems) { $item in
                    HStack(spacing: MacTheme.spacing8) {
                        Button {
                            item.completed.toggle()
                            persistChecklist()
                        } label: {
                            Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14))
                                .foregroundStyle(item.completed ? MacTheme.switchTint : MacTheme.mutedText)
                        }
                        .buttonStyle(.plain)
                        .macClickablePointer()

                        TextField("Item", text: $item.title)
                            .font(.system(size: 13))
                            .textFieldStyle(.plain)
                            .strikethrough(item.completed, color: MacTheme.mutedText)
                            .foregroundStyle(item.completed ? MacTheme.mutedText : MacTheme.textPrimary)
                            .onSubmit { persistChecklist() }

                        Spacer()

                        Button {
                            removeChecklistItem(id: item.id)
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(MacTheme.mutedText)
                        }
                        .buttonStyle(.plain)
                        .macClickablePointer()
                        .help("Remove item")
                    }
                    .padding(.horizontal, MacTheme.spacing8)
                    .padding(.vertical, MacTheme.spacing6)
                    .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius))
                    .overlay(RoundedRectangle(cornerRadius: MacTheme.buttonRadius).stroke(MacTheme.cardBorder, lineWidth: 0.5))
                }

                Button {
                    addChecklistItem()
                } label: {
                    HStack(spacing: MacTheme.spacing6) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 12))
                        Text("Add item")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(MacTheme.textSecondary)
                    .padding(.horizontal, MacTheme.spacing8)
                    .padding(.vertical, MacTheme.spacing6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MacTheme.surfaceCard.opacity(0.5), in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: MacTheme.buttonRadius)
                            .stroke(MacTheme.cardBorder.opacity(0.6), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    )
                }
                .buttonStyle(.plain)
                .macClickablePointer()
            }
        }
    }

    private func addChecklistItem() {
        let nextOrder = (checklistItems.map(\.order).max() ?? -1) + 1
        checklistItems.append(ChecklistItem(title: "", completed: false, order: nextOrder))
        persistChecklist()
    }

    private func removeChecklistItem(id: UUID) {
        checklistItems.removeAll { $0.id == id }
        // Re-normalise ordering so the column stays compact after removals.
        for index in checklistItems.indices {
            checklistItems[index].order = index
        }
        persistChecklist()
    }

    /// Live save: checklist edits land in SwiftData immediately so the user
    /// never loses a checked box if they navigate away without hitting Save.
    private func persistChecklist() {
        task.checklistItems = checklistItems
        task.updatedAt = .now
        try? modelContext.save()
    }

    // MARK: - Attachments

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing8) {
            Text("ATTACHMENTS")
                .font(MacTheme.sectionHeaderFont())
                .foregroundStyle(MacTheme.mutedText)
                .tracking(0.8)

            VStack(spacing: MacTheme.spacing6) {
                ForEach(attachmentPaths, id: \.self) { path in
                    attachmentRow(path: path)
                }

                Button {
                    presentAttachmentPicker()
                } label: {
                    HStack(spacing: MacTheme.spacing6) {
                        Image(systemName: "paperclip.badge.plus")
                            .font(.system(size: 12))
                        Text("Attach file")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(MacTheme.textSecondary)
                    .padding(.horizontal, MacTheme.spacing8)
                    .padding(.vertical, MacTheme.spacing6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MacTheme.surfaceCard.opacity(0.5), in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: MacTheme.buttonRadius)
                            .stroke(MacTheme.cardBorder.opacity(0.6), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    )
                }
                .buttonStyle(.plain)
                .macClickablePointer()
            }
        }
    }

    @ViewBuilder
    private func attachmentRow(path: String) -> some View {
        let filename = (path as NSString).lastPathComponent
        HStack(spacing: MacTheme.spacing8) {
            Image(systemName: attachmentIcon(for: filename))
                .font(.system(size: 13))
                .foregroundStyle(MacTheme.mutedText)
                .frame(width: 18)

            Text(filename)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(MacTheme.textPrimary)

            Spacer()

            Button {
                removeAttachment(path: path)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.mutedText)
            }
            .buttonStyle(.plain)
            .macClickablePointer()
            .help("Remove attachment")
        }
        .padding(.horizontal, MacTheme.spacing8)
        .padding(.vertical, MacTheme.spacing6)
        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius))
        .overlay(RoundedRectangle(cornerRadius: MacTheme.buttonRadius).stroke(MacTheme.cardBorder, lineWidth: 0.5))
    }

    private func attachmentIcon(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "bmp", "tiff":
            return "photo"
        case "pdf":
            return "doc.richtext"
        case "mp4", "mov", "m4v", "avi":
            return "film"
        case "mp3", "wav", "m4a", "aac":
            return "music.note"
        case "zip", "tar", "gz":
            return "archivebox"
        default:
            return "doc"
        }
    }

    /// Open NSOpenPanel, copy the chosen file(s) into the task's attachment
    /// directory, and store the resulting relative paths. Storing relative
    /// paths keeps tasks portable across container moves (sandbox migrations,
    /// Application Support relocation, etc.).
    private func presentAttachmentPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.title = "Attach file"
        panel.prompt = "Attach"
        guard panel.runModal() == .OK else { return }

        var newPaths: [String] = []
        for sourceURL in panel.urls {
            // Soft 50MB cap: warn before copying large files into Application
            // Support so users don't accidentally bloat the task store with
            // a 5GB movie. They can override per-file.
            let sizeLimit: Int64 = 50 * 1024 * 1024
            if let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
               let size = attrs[.size] as? NSNumber,
               size.int64Value > sizeLimit {
                let alert = NSAlert()
                let mb = Double(size.int64Value) / 1024.0 / 1024.0
                alert.messageText = "Large file"
                alert.informativeText = String(
                    format: "%@ is %.1f MB. Attaching large files can slow down the app. Attach anyway?",
                    sourceURL.lastPathComponent,
                    mb
                )
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Attach")
                alert.addButton(withTitle: "Skip")
                let response = alert.runModal()
                if response != .alertFirstButtonReturn {
                    AppLogger.shared.log("[Tasks] skipped large attachment (\(Int(mb)) MB): \(sourceURL.lastPathComponent)")
                    continue
                }
                AppLogger.shared.log("[Tasks] attached large file (\(Int(mb)) MB): \(sourceURL.lastPathComponent)")
            }
            if let storedPath = copyAttachmentToTaskDirectory(sourceURL: sourceURL) {
                newPaths.append(storedPath)
            }
        }
        guard !newPaths.isEmpty else { return }
        attachmentPaths.append(contentsOf: newPaths)
        persistAttachments()
    }

    /// Copies `sourceURL` into `Application Support/TaskAttachments/<taskId>/`,
    /// disambiguating filename collisions by suffixing a counter. Returns the
    /// stored path relative to that directory so callers don't have to know
    /// the absolute container path. `nil` means the copy failed and the file
    /// should not be added to the attachments list.
    private func copyAttachmentToTaskDirectory(sourceURL: URL) -> String? {
        guard let taskDir = attachmentDirectory() else { return nil }
        do {
            try FileManager.default.createDirectory(at: taskDir, withIntermediateDirectories: true)
        } catch {
            print("[MacTaskDetailSheet] Failed to create attachment dir: \(error)")
            return nil
        }

        let originalName = sourceURL.lastPathComponent
        var candidateName = originalName
        var counter = 1
        let baseName = (originalName as NSString).deletingPathExtension
        let ext = (originalName as NSString).pathExtension
        while FileManager.default.fileExists(atPath: taskDir.appendingPathComponent(candidateName).path) {
            counter += 1
            candidateName = ext.isEmpty
                ? "\(baseName) \(counter)"
                : "\(baseName) \(counter).\(ext)"
        }
        let destURL = taskDir.appendingPathComponent(candidateName)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            return candidateName
        } catch {
            print("[MacTaskDetailSheet] Failed to copy attachment \(originalName): \(error)")
            return nil
        }
    }

    /// Per-task attachment directory inside Application Support. Returns nil
    /// only if Application Support itself is unavailable (extremely unusual).
    private func attachmentDirectory() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport
            .appendingPathComponent("TaskAttachments", isDirectory: true)
            .appendingPathComponent(task.id.uuidString, isDirectory: true)
    }

    private func removeAttachment(path: String) {
        attachmentPaths.removeAll { $0 == path }
        if let dir = attachmentDirectory() {
            // Best-effort delete: missing files are fine, just keep the list in sync.
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(path))
        }
        persistAttachments()
    }

    private func persistAttachments() {
        task.attachmentPaths = attachmentPaths
        task.updatedAt = .now
        try? modelContext.save()
    }

    private func saveChanges() {
        task.title = editedTitle
        task.taskDescription = editedDescription
        task.status = editedStatus
        task.priority = editedPriority
        task.dueDate = hasDueDate ? editedDueDate : nil
        task.folder = folders.first(where: { $0.id == selectedFolderID })
        task.recurrenceRule = recurrence.storedValue
        // Checklist and attachments persist live, but re-write here too so a
        // Save click after in-place TextField edits flushes the latest values.
        task.checklistItems = checklistItems
        task.attachmentPaths = attachmentPaths
        task.updatedAt = .now
        // Mark dirty so the sync flush uploads the edit — without this, edits to
        // an already-`.synced` task stay local forever (retry only picks up
        // `.pendingUpload`/`.failed`). The launch/foreground/reconnect flush
        // (`MacAppServices.flushPendingSync`) then uploads it.
        task.syncState = .pendingUpload
        try? modelContext.save()
    }

    /// True when at least one draft field diverges from the underlying task.
    /// Drives the Save button's enabled state so the user gets a visible
    /// "nothing to save" signal instead of clicking into a no-op.
    private var hasUnsavedChanges: Bool {
        let normalizedDueDate = hasDueDate ? editedDueDate : nil
        return editedTitle != task.title
            || editedDescription != task.taskDescription
            || editedStatus != task.status
            || editedPriority != task.priority
            || normalizedDueDate != task.dueDate
            || selectedFolderID != task.folderID
            || recurrence.storedValue != task.recurrenceRule
            || checklistItems != task.checklistItems
            || attachmentPaths != task.attachmentPaths
    }
}

// MARK: - Recurrence helpers

/// Returns the next occurrence after `date` based on a simple keyword rule
/// (`daily`, `weekly`, `monthly`, `yearly`) or an RRULE that contains a
/// matching FREQ token. Returns `nil` for unsupported rules — callers should
/// treat that as "no next occurrence" and leave the task as a one-off.
///
/// Kept as a free function so it can be reused by future code (e.g. completion
/// toggles) without coupling to `MacTaskDetailSheet`.
func nextRecurrence(after date: Date, rule: String) -> Date? {
    let calendar = Calendar.current
    let normalized = rule.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return nil }

    let component: Calendar.Component?
    if normalized == "daily" || normalized.contains("freq=daily") {
        component = .day
    } else if normalized == "weekly" || normalized.contains("freq=weekly") {
        component = .weekOfYear
    } else if normalized == "monthly" || normalized.contains("freq=monthly") {
        component = .month
    } else if normalized == "yearly" || normalized.contains("freq=yearly") {
        component = .year
    } else {
        component = nil
    }
    guard let component else { return nil }
    return calendar.date(byAdding: component, value: 1, to: date)
}

extension Notification.Name {
    /// Posted by `MacTaskRow.toggleCompletion` when a recurring task is
    /// "completed" — instead of being marked done, its due date is bumped to
    /// the next occurrence. The userInfo dict carries `title: String` and
    /// `nextDueDate: Date` for a toast in the parent view.
    static let todusTaskRescheduledByRecurrence = Notification.Name("TodusTaskRescheduledByRecurrence")
}

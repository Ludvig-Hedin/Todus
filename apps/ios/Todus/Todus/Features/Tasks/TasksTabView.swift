import SwiftUI
import SwiftData

/// The Tasks tab — extracted from the original MiniTaskApp RootView.
/// Contains the view mode picker, folder strip, search bar, and task list/board/table/calendar views.
struct TasksTabView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(
        sort: [
            SortDescriptor(\FolderRecord.position, order: .forward),
            SortDescriptor(\FolderRecord.createdAt, order: .forward),
        ]
    )
    private var folders: [FolderRecord]

    @State private var searchText = ""
    /// Task opened via AI chat card deep navigation
    @State private var pendingTaskRecord: TaskRecord?
    @State private var selectedFolder: FolderRecord?
    @State private var showFolderEditSheet = false
    @State private var showClearCompletedConfirm = false
    @State private var folderToDelete: FolderRecord?
    @Namespace private var taskViewModeSegmentNamespace

    @State private var headerHeight: CGFloat = 100
    /// Visual gap between the pinned search bar and the first row of content
    /// (16–20pt is the standard breathing room across all four task views).
    private let scrimTail: CGFloat = 18

    /// Holds the in-flight deep-nav task so a rapid second `pendingTaskId` arrival
    /// cancels the previous delayed presentation instead of stacking sheets.
    /// (Bug H6 — replaces GCD asyncAfter with a cancellable structured Task.)
    @State private var pendingNavTask: Task<Void, Never>?

    /// Live counts driving the "Today N" / "Overdue N" header chips.
    /// SwiftData @Query observes any TaskRecord changes, recomputing on the
    /// fly. We intentionally don't filter by folder here — the header is a
    /// global today-snapshot, not folder-scoped.
    @Query(filter: #Predicate<TaskRecord> { task in task.statusRawValue != "done" })
    private var openTasks: [TaskRecord]

    /// Completed tasks — used only to gate whether the "All clear" celebration
    /// chip should appear. Showing "All clear" on a brand-new install with
    /// zero tasks ever felt nonsensical. (UX P11.)
    @Query(filter: #Predicate<TaskRecord> { task in task.statusRawValue == "done" })
    private var doneTasks: [TaskRecord]

    var body: some View {
        ZStack(alignment: .top) {
            AppTheme.backgroundTop
                .ignoresSafeArea()
                .onTapGesture { self.dismissKeyboard() }

            // Scrollable task content fills the full screen; inset below the pinned header.
            // List mode renders the Folders section below the tasks so the whole page
            // scrolls together as one continuous surface.
            Group {
                switch services.selectedViewMode {
                case .list:
                    InboxView(
                        captureService: services.captureService,
                        selectedFolderID: nil,
                        restrictToInbox: true,
                        searchText: searchText,
                        sortOrder: services.taskSortOrder,
                        footer: { foldersFooter }
                    )
                        .padding(.horizontal, 10)
                case .board:
                    BoardView(
                        captureService: services.captureService,
                        selectedFolderID: nil,
                        restrictToInbox: true,
                        searchText: searchText,
                        sortOrder: services.taskSortOrder
                    )
                case .table:
                    TaskTableView(
                        captureService: services.captureService,
                        selectedFolderID: nil,
                        restrictToInbox: true,
                        searchText: searchText,
                        sortOrder: services.taskSortOrder
                    )
                case .calendar:
                    CalendarTaskView(searchText: searchText, sortOrder: services.taskSortOrder)
                        .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentMargins(.bottom, 130, for: .scrollContent)
            .safeAreaInset(edge: .top) {
                Color.clear.frame(height: headerHeight + scrimTail)
            }
            .refreshable {
                await reload()
            }

            // Pinned header overlay with transparent scrim — content scrolls under it.
            VStack(spacing: 8) {
                AppTopHeader(title: "Tasks") {
                    HStack(spacing: 8) {
                        Text("Tasks")
                            .font(.system(size: 18, weight: .bold))
                            .tracking(-0.3)
                            .foregroundStyle(.primary)
                        if services.captureService.isSyncingSharedFolders {
                            InlineRefreshBadge(label: "Syncing")
                        }
                        // Live "what matters now" chips so the user gets a
                        // one-glance read of their day right from the header.
                        // Empty state is "Clear" — celebrates the inbox-zero moment.
                        todayHeaderChips
                        Spacer()
                        // Discoverable + button on iOS — previously only macOS had a
                        // visible "+ Add Task" affordance; iOS users had to find the
                        // composer via the central tab-bar create action.
                        // (UX assessment QW11.)
                        Button {
                            services.requestCreateSheet = .task
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 28, height: 28)
                                .background(AppTheme.surfaceSecondary, in: Circle())
                                .overlay(Circle().stroke(AppTheme.strongBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        // Expands hit-area to ≥44pt without enlarging the
                        // visible 28pt affordance, matching other icon
                        // buttons across the app. (UX P4.)
                        .minTouchTarget()
                        .accessibilityLabel("Add task")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)

                header
                    .padding(.horizontal, 16)

                searchSortBar
                    .padding(.horizontal, 16)
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
            await services.captureService.syncSharedFolders(in: modelContext)
            await services.captureService.fetchFolderSummary(in: modelContext)
        }
        // Deep navigation from AI chat cards — open task detail sheet
        .onAppear { consumePendingTaskNavigation() }
        .onChange(of: services.pendingTaskId) { _, _ in consumePendingTaskNavigation() }
        .onDisappear {
            // Cancel any in-flight delayed sheet presentation so it doesn't
            // fire after this view has gone away (Bug H6).
            pendingNavTask?.cancel()
            pendingNavTask = nil
        }
        .sheet(item: $pendingTaskRecord) { task in
            TaskDetailSheet(task: task)
        }
        .sheet(item: $selectedFolder) { folder in
            NavigationStack {
                FolderDetailView(folder: folder)
            }
            .presentationDragIndicator(.visible)
            .appSheetBackground()
        }
        .sheet(isPresented: $showFolderEditSheet) {
            FolderEditSheet(mode: .create)
                .appSheetBackground()
        }
        // Header ellipsis menu actions
        .onChange(of: services.tasksSyncRemindersTick) { _, _ in
            Task {
                await services.remindersSyncService.refreshFromReminders(in: modelContext)
            }
        }
        .onChange(of: services.tasksClearCompletedTick) { _, _ in
            showClearCompletedConfirm = true
        }
        .confirmationDialog(
            "Clear all completed tasks?",
            isPresented: $showClearCompletedConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Completed", role: .destructive) {
                services.captureService.clearCompletedTasks(filteredBy: nil, in: modelContext)
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete folder?",
            isPresented: Binding(
                get: { folderToDelete != nil },
                set: { if !$0 { folderToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let folder = folderToDelete else { return }
                services.captureService.deleteFolder(folder, in: modelContext)
                folderToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                folderToDelete = nil
            }
        }
    }

    /// Refreshes task-related data sources. Triggered by pull-to-refresh on the task list.
    /// Awaits the slowest call (shared folder sync) so SwiftUI keeps the spinner visible
    /// while data is in flight. SwiftData @Query observers then update the visible list
    /// automatically once new records arrive.
    private func reload() async {
        await services.captureService.syncSharedFolders(in: modelContext)
        await services.captureService.fetchFolderSummary(in: modelContext)
        await services.remindersSyncService.refreshFromReminders(in: modelContext)
    }

    /// Picks up a pending task ID set by AI chat card navigation and opens the detail sheet.
    /// The 300ms delay lets the underlying navigation settle before the sheet appears;
    /// the surrounding `pendingNavTask` makes that delay cancellable so a second
    /// arrival (or `onDisappear`) supersedes the first instead of stacking sheets.
    /// (Bug H6 — was a bare `DispatchQueue.main.asyncAfter` with no cancel path.)
    private func consumePendingTaskNavigation() {
        guard let taskId = services.pendingTaskId else { return }
        services.pendingTaskId = nil
        let descriptor = FetchDescriptor<TaskRecord>(
            predicate: #Predicate { task in task.id == taskId }
        )
        guard let task = try? modelContext.fetch(descriptor).first else { return }

        pendingNavTask?.cancel()
        pendingNavTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            pendingTaskRecord = task
        }
    }

    // MARK: - Header chips

    /// Live "Overdue / Today" capsules in the header. Renders nothing
    /// when there's nothing pressing. Tapping a chip flips the sort to
    /// `.smart` so the user lands on that bucket. The chip is the single
    /// most important orientation cue — "do I have anything urgent?".
    @ViewBuilder
    private var todayHeaderChips: some View {
        let now = Date()
        let cal = Calendar.current
        let overdue = openTasks.filter { task in
            guard let due = task.dueDate else { return false }
            return due < now && !cal.isDateInToday(due)
        }.count
        let today = openTasks.filter { task in
            guard let due = task.dueDate else { return false }
            return cal.isDateInToday(due)
        }.count

        HStack(spacing: 6) {
            if overdue > 0 {
                headerChip(
                    label: "\(overdue) overdue",
                    icon: "exclamationmark.circle.fill",
                    tint: Color(red: 0.85, green: 0.30, blue: 0.25)
                )
            }
            if today > 0 {
                headerChip(
                    label: "\(today) today",
                    icon: "sun.max.fill",
                    tint: Color(red: 0.88, green: 0.55, blue: 0.20)
                )
            }
        }
    }

    private func headerChip(label: String, icon: String, tint: Color) -> some View {
        Button {
            // Chip-tap focuses the smart sort so the bucket the user just
            // glanced at becomes the visible scroll structure.
            services.taskSortOrder = .smart
            services.selectedViewMode = .list
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.22), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            viewModePicker
        }
    }

    /// Matches macOS Calendar segmented control: recessed track + bright selected pill + shadow.
    private var viewModePicker: some View {
        HStack(spacing: 2) {
            ForEach(TaskViewMode.allCases) { mode in
                let isSelected = services.selectedViewMode == mode
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        services.selectedViewMode = mode
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        Text(mode.shortTitle)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    }
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 6)
                    .background {
                        if isSelected {
                            Capsule(style: .continuous)
                                .fill(AppTheme.segmentedSelectedPill)
                                .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
                                .matchedGeometryEffect(id: "task-view-mode-pill", in: taskViewModeSegmentNamespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(AppTheme.segmentedTrack, in: Capsule(style: .continuous))
    }

    // MARK: - Search + Sort Bar

    private var searchSortBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.mutedText)
                .padding(.leading, 2)

            TextField("Search tasks…", text: $searchText)
                .font(.system(size: 12, weight: .medium))
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.mutedText)
                }
                .buttonStyle(.plain)
                .minTouchTarget()
            }

            Divider().frame(height: 10)

            Menu {
                ForEach(TaskSortOrder.allCases) { order in
                    Button {
                        services.taskSortOrder = order
                    } label: {
                        let icon = services.taskSortOrder == order ? "checkmark" : order.systemImage
                        Label(order.title, systemImage: icon)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(services.taskSortOrder.title)
                        .font(.system(size: 10, weight: .semibold))
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(AppTheme.mutedText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppTheme.surfaceSecondary, in: Capsule())
                .minTouchTarget()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(AppTheme.surfacePrimary, in: Capsule())
        .overlay(
            Capsule()
                .stroke(AppTheme.strongBorder, lineWidth: 1)
        )
    }

    // MARK: - Folders Footer

    /// Folders section rendered below the task list. Scrolls together with tasks
    /// as one continuous surface — no nested scroll views, no fixed-height cap.
    @ViewBuilder
    private var foldersFooter: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.subtleText)
                Text("Folders")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(folders) { folder in
                    Button {
                        selectedFolder = folder
                    } label: {
                        FolderCardView(folder: folder, layout: .grid)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            selectedFolder = folder
                        } label: {
                            Label("Open", systemImage: "arrow.up.right.square")
                        }
                        Button(role: .destructive) {
                            folderToDelete = folder
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                NewFolderCard(layout: .grid) {
                    showFolderEditSheet = true
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }
}

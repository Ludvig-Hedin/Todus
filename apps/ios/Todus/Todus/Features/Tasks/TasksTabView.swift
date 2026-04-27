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
    @State private var taskSortOrder: TaskSortOrder = .newest
    /// Task opened via AI chat card deep navigation
    @State private var pendingTaskRecord: TaskRecord?
    @State private var selectedFolder: FolderRecord?
    @State private var showFolderEditSheet = false
    @State private var showClearCompletedConfirm = false
    @State private var folderToDelete: FolderRecord?
    @Namespace private var taskViewModeSegmentNamespace

    @State private var headerHeight: CGFloat = 100
    private let scrimTail: CGFloat = 32

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
                        sortOrder: taskSortOrder,
                        footer: { foldersFooter }
                    )
                        .padding(.horizontal, 10)
                case .board:
                    BoardView(
                        captureService: services.captureService,
                        selectedFolderID: nil,
                        restrictToInbox: true,
                        searchText: searchText,
                        sortOrder: taskSortOrder
                    )
                case .table:
                    TaskTableView(
                        captureService: services.captureService,
                        selectedFolderID: nil,
                        restrictToInbox: true,
                        searchText: searchText,
                        sortOrder: taskSortOrder
                    )
                case .calendar:
                    CalendarTaskView(searchText: searchText, sortOrder: taskSortOrder)
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
    private func consumePendingTaskNavigation() {
        guard let taskId = services.pendingTaskId else { return }
        services.pendingTaskId = nil
        let descriptor = FetchDescriptor<TaskRecord>(
            predicate: #Predicate { task in task.id == taskId }
        )
        if let task = try? modelContext.fetch(descriptor).first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pendingTaskRecord = task
            }
        }
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.mutedText)

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

            Divider().frame(height: 12)

            Menu {
                ForEach(TaskSortOrder.allCases) { order in
                    Button {
                        taskSortOrder = order
                    } label: {
                        Label(order.title, systemImage: taskSortOrder == order ? "checkmark" : order.systemImage)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(taskSortOrder.title)
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
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .frame(minHeight: 32)
        // Use surfacePrimary (white in light / 0.11 in dark) so the bar is clearly
        // visible against the backgroundTop (0.94 in light / 0.05 in dark).
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

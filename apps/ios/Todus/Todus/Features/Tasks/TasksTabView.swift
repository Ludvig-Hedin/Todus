import SwiftUI
import SwiftData

/// The Tasks tab — extracted from the original MiniTaskApp RootView.
/// Contains the view mode picker, folder strip, search bar, and task list/board/table/calendar views.
struct TasksTabView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FolderRecord.createdAt) private var folders: [FolderRecord]

    @State private var searchText = ""
    @State private var taskSortOrder: TaskSortOrder = .newest
    /// Task opened via AI chat card deep navigation
    @State private var pendingTaskRecord: TaskRecord?

    var body: some View {
        ZStack {
            AppTheme.backgroundTop
                .ignoresSafeArea()
                .onTapGesture { self.dismissKeyboard() }

            VStack(spacing: 10) {
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

                if !folders.isEmpty {
                    folderStrip
                        .padding(.horizontal, 16)
                }

                searchSortBar
                    .padding(.horizontal, 16)

                Group {
                    switch services.selectedViewMode {
                    case .list:
                        InboxView(
                            captureService: services.captureService,
                            selectedFolderID: services.selectedFolderID,
                            searchText: searchText,
                            sortOrder: taskSortOrder
                        )
                            .padding(.horizontal, 16)
                    case .board:
                        BoardView(
                            captureService: services.captureService,
                            selectedFolderID: services.selectedFolderID,
                            searchText: searchText,
                            sortOrder: taskSortOrder
                        )
                    case .table:
                        TaskTableView(
                            captureService: services.captureService,
                            selectedFolderID: services.selectedFolderID,
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
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await services.captureService.syncSharedFolders(in: modelContext)
        }
        // Deep navigation from AI chat cards — open task detail sheet
        .onAppear { consumePendingTaskNavigation() }
        .onChange(of: services.pendingTaskId) { _, _ in consumePendingTaskNavigation() }
        .sheet(item: $pendingTaskRecord) { task in
            TaskDetailSheet(task: task)
        }
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

    private var viewModePicker: some View {
        HStack(spacing: 2) {
            ForEach(TaskViewMode.allCases) { mode in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        services.selectedViewMode = mode
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 14, weight: .semibold))

                        Text(mode.shortTitle)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(
                        services.selectedViewMode == mode ? .primary : AppTheme.mutedText
                    )
                    .frame(maxWidth: .infinity)
                    .background(
                        services.selectedViewMode == mode
                            ? AppTheme.surfaceSecondary
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Search + Sort Bar

    private var searchSortBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.mutedText)

            TextField("Search tasks…", text: $searchText)
                .font(.system(size: 13, weight: .medium))
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.mutedText)
                }
                .buttonStyle(.plain)
                .minTouchTarget()
            }

            Divider().frame(height: 14)

            Menu {
                ForEach(TaskSortOrder.allCases) { order in
                    Button {
                        taskSortOrder = order
                    } label: {
                        Label(order.title, systemImage: taskSortOrder == order ? "checkmark" : order.systemImage)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(taskSortOrder.title)
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(AppTheme.mutedText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.surfaceSecondary, in: Capsule())
                .minTouchTarget()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        // Use surfacePrimary (white in light / 0.11 in dark) so the bar is clearly
        // visible against the backgroundTop (0.94 in light / 0.05 in dark).
        .background(AppTheme.surfacePrimary, in: Capsule())
        .overlay(
            Capsule()
                .stroke(AppTheme.strongBorder, lineWidth: 1)
        )
    }

    // MARK: - Folder Strip

    private var folderStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    services.selectFolder(nil)
                } label: {
                    Text("All")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(-0.1)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(services.selectedFolderID == nil ? AppTheme.accent.opacity(0.12) : AppTheme.surfacePrimary, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(services.selectedFolderID == nil ? AppTheme.accent.opacity(0.24) : AppTheme.cardBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                ForEach(folders) { folder in
                    Button {
                        services.selectFolder(folder)
                    } label: {
                        Text(folder.name)
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(-0.1)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(services.selectedFolderID == folder.id ? AppTheme.accent.opacity(0.12) : AppTheme.surfacePrimary, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(services.selectedFolderID == folder.id ? AppTheme.accent.opacity(0.24) : AppTheme.cardBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }
}

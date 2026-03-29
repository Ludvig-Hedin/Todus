import SwiftUI
import SwiftData

/// The Tasks tab — extracted from the original MiniTaskApp RootView.
/// Contains the view mode picker, folder strip, search bar, and task list/board/table/calendar views.
struct TasksTabView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FolderRecord.createdAt) private var folders: [FolderRecord]
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]

    @State private var composerText = ""
    @State private var searchText = ""
    @State private var taskSortOrder: TaskSortOrder = .newest
    /// Task opened via AI chat card deep navigation
    @State private var pendingTaskRecord: TaskRecord?
    /// Keyboard height — used to lift the composer above the keyboard since
    /// MainTabView ignores keyboard safe area (to keep the tab bar in place).
    @StateObject private var keyboard = KeyboardObserver()

    var body: some View {
        ZStack {
            AppTheme.backgroundTop
                .ignoresSafeArea()
                .onTapGesture { self.dismissKeyboard() }

            VStack(spacing: 12) {
                AppTopHeader(title: "Tasks")
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
                        InboxView(searchText: searchText, sortOrder: taskSortOrder)
                            .padding(.horizontal, 16)
                    case .board:
                        BoardView()
                    case .table:
                        TaskTableView()
                    case .calendar:
                        CalendarTaskView(searchText: searchText)
                            .padding(.horizontal, 16)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            CaptureComposer(text: $composerText) { attachmentNames, folder, dueDate in
                let raw = composerText
                composerText = ""
                withAnimation(.snappy(duration: 0.18)) {
                    services.captureService.capture(
                        rawComposerText: raw,
                        attachmentNames: attachmentNames,
                        selectedFolder: folder,
                        overrideDueDate: dueDate,
                        in: modelContext
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            // When keyboard is visible, push the composer above it.
            // MainTabView uses .ignoresSafeArea(.keyboard) to keep the tab bar at the
            // bottom, so we manually add keyboard height here for the composer.
            .padding(.bottom, keyboard.isVisible ? keyboard.height : 8)
            .animation(.easeOut(duration: 0.25), value: keyboard.height)
            .background(.clear)
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
        if let task = allTasks.first(where: { $0.id == taskId }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pendingTaskRecord = task
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            viewModePicker
        }
        .padding(.vertical, 12)
    }

    private var viewModePicker: some View {
        HStack(spacing: 2) {
            ForEach(TaskViewMode.allCases) { mode in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        services.selectedViewMode = mode
                    }
                } label: {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(
                            services.selectedViewMode == mode ? .primary : AppTheme.mutedText
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.mutedText)

            TextField("Search tasks…", text: $searchText)
                .font(.system(size: 14, weight: .medium))
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.mutedText)
                }
                .buttonStyle(.plain)
                .minTouchTarget()
            }

            Divider().frame(height: 16)

            Menu {
                ForEach(TaskSortOrder.allCases) { order in
                    Button {
                        taskSortOrder = order
                    } label: {
                        Label(order.title, systemImage: taskSortOrder == order ? "checkmark" : order.systemImage)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
                    .minTouchTarget()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        // Use surfacePrimary (white in light / 0.11 in dark) so the bar is clearly
        // visible against the backgroundTop (0.94 in light / 0.05 in dark).
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
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

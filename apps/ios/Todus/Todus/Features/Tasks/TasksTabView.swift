import SwiftUI
import SwiftData
import UIKit

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
    @State private var showOrganizeSheet = false
    @State private var showClearCompletedConfirm = false
    @State private var folderToDelete: FolderRecord?
    @Namespace private var taskViewModeSegmentNamespace

    @State private var headerHeight: CGFloat = 100
    /// Visual gap between the pinned search bar and the first row of content.
    private let scrimTail: CGFloat = 6

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
            //
            // All scroll modifiers (safeAreaInset, contentMargins, refreshable,
            // onScrollGeometryChange) are applied PER-CASE rather than on the Group.
            // BoardView is a horizontal-only ScrollView — `.refreshable` and a top
            // safeAreaInset both reserve permanent unscrollable top space on it,
            // which is what produced the massive gap. Board receives the header
            // height as `topInset` and applies padding inside the HStack instead.
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
                    .safeAreaInset(edge: .top) {
                        Color.clear.frame(height: headerHeight + scrimTail)
                    }
                    .contentMargins(.bottom, 130, for: .scrollContent)
                    .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { old, new in hideTabBarOnScroll(old, new) }
                    .refreshable { await reload() }
                case .board:
                    BoardView(
                        captureService: services.captureService,
                        selectedFolderID: nil,
                        restrictToInbox: true,
                        searchText: searchText,
                        sortOrder: services.taskSortOrder,
                        topInset: headerHeight + scrimTail
                    )
                case .table:
                    TaskTableView(
                        captureService: services.captureService,
                        selectedFolderID: nil,
                        restrictToInbox: true,
                        searchText: searchText,
                        sortOrder: services.taskSortOrder
                    )
                    .safeAreaInset(edge: .top) {
                        Color.clear.frame(height: headerHeight + scrimTail)
                    }
                    .contentMargins(.bottom, 130, for: .scrollContent)
                    .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { old, new in hideTabBarOnScroll(old, new) }
                    .refreshable { await reload() }
                case .calendar:
                    CalendarTaskView(searchText: searchText, sortOrder: services.taskSortOrder)
                        .padding(.horizontal, 16)
                        .safeAreaInset(edge: .top) {
                            Color.clear.frame(height: headerHeight + scrimTail)
                        }
                        .contentMargins(.bottom, 130, for: .scrollContent)
                        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { old, new in hideTabBarOnScroll(old, new) }
                        .refreshable { await reload() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
        // Search query seeded by GlobalSearchView's "See all N in Tasks" row
        .onAppear { consumePendingSearchSeed() }
        .onChange(of: services.tasksSearchSeed) { _, _ in consumePendingSearchSeed() }
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
        .sheet(isPresented: $showOrganizeSheet) {
            OrganizeReviewSheet()
                .presentationDragIndicator(.visible)
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

    /// Hides the tab bar on downward scroll and reveals on upward. Shared across
    /// list / table / calendar cases so each scroll observer behaves identically.
    /// Parameter labels are unlabeled (`_`) to match the `(T, T) -> Void` shape
    /// `onScrollGeometryChange` expects when passed as a function reference.
    private func hideTabBarOnScroll(_ old: CGFloat, _ new: CGFloat) {
        let delta = new - old
        if delta > 8 && new > 40 {
            withAnimation(.easeOut(duration: 0.2)) { services.hideTabBar = true }
        } else if delta < -8 {
            withAnimation(.easeOut(duration: 0.2)) { services.hideTabBar = false }
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

    /// Picks up a search query seeded by GlobalSearchView's "See all N in Tasks" row
    /// and applies it to this tab's own search field (flows into `InboxView` /
    /// `BoardView` / `TaskTableView` / `CalendarTaskView` via their `searchText` param).
    private func consumePendingSearchSeed() {
        guard let seed = services.tasksSearchSeed else { return }
        services.tasksSearchSeed = nil
        searchText = seed
    }

    // MARK: - Header chips

    /// Live "Overdue / Today" capsules in the header. Renders nothing
    /// when there's nothing pressing. Passive stat pills — the single most
    /// important orientation cue: "do I have anything urgent?".
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
        // Passive stat label. These looked like filter buttons but only flipped
        // the sort mode — a no-op in the default list+smart configuration — so
        // tapping "3 overdue" appeared broken. Render as plain status pills
        // until a real per-bucket filter exists.
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.22), lineWidth: 0.5))
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
                            .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                        Text(mode.shortTitle)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    }
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 8)
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
        .padding(4)
        .background(AppTheme.segmentedTrack, in: Capsule(style: .continuous))
    }

    // MARK: - Search + Sort Bar

    private var searchSortBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.mutedText)
                .padding(.leading, 2)

            TextField("Search tasks…", text: $searchText)
                .font(.system(size: 14, weight: .medium))
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

            // AI + rules inbox cleanup. Opens a review sheet — nothing moves
            // without an explicit Apply. (Tasks UX overhaul.)
            Button {
                showOrganizeSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Organize")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(AppTheme.secondaryAccent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.secondaryAccent.opacity(0.10), in: Capsule())
                .minTouchTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Auto-organize tasks into folders")

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
                        .font(.system(size: 12, weight: .semibold))
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
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
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
                    DroppableFolderCard(folder: folder) {
                        selectedFolder = folder
                    } onDelete: {
                        folderToDelete = folder
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

/// Folder card that accepts a dragged task (UUID-string payload from
/// `TaskRowView`'s `.draggable`) and moves it into the folder on drop.
/// Highlights with the folder accent while a drag hovers over it.
private struct DroppableFolderCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    let folder: FolderRecord
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var isTargeted = false

    private var accent: Color {
        if let hex = folder.colorHex, !hex.isEmpty {
            return Color(hex: hex)
        }
        return AppTheme.subtleText
    }

    var body: some View {
        Button(action: onOpen) {
            FolderCardView(folder: folder, layout: .grid)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onOpen) {
                Label("Open", systemImage: "arrow.up.right.square")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(accent, lineWidth: isTargeted ? 2 : 0)
        )
        .scaleEffect(isTargeted ? 1.03 : 1.0)
        .animation(AppTheme.Motion.fast, value: isTargeted)
        .dropDestination(for: String.self) { items, _ in
            guard
                let payload = items.first,
                let taskID = UUID(uuidString: payload)
            else { return false }
            let descriptor = FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == taskID })
            guard let task = try? modelContext.fetch(descriptor).first else { return false }
            task.suggestedFolderID = nil
            withAnimation(AppTheme.Motion.base) {
                services.captureService.move(task, to: folder, in: modelContext)
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return true
        } isTargeted: { targeting in
            isTargeted = targeting
        }
    }
}

import SwiftUI
import SwiftData

struct InboxView<Footer: View>: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]

    let captureService: TaskCaptureService
    let selectedFolderID: UUID?
    /// When true and no folder is selected, only show tasks that are not in any folder
    /// (a true "Inbox"). Used by the redesigned Tasks tab where folders show as cards
    /// below the list, so the list itself becomes the orphan-task surface.
    var restrictToInbox: Bool = false
    @State private var taskPendingMove: TaskRecord?
    @State private var selectedTask: TaskRecord?
    @State private var showsClearCompletedConfirmation = false

    /// Filter text from the home search bar
    var searchText: String = ""
    /// Sort order selected from the home sort menu
    var sortOrder: TaskSortOrder = .smart

    /// Optional content rendered below the task list, scrolling together as one page.
    /// Used by the Tasks tab to surface the Folders grid at the bottom.
    @ViewBuilder var footer: () -> Footer

    // Cached derived arrays — recomputed only when inputs change (not on every render).
    // Computing filtered+sorted arrays in computed properties re-ran on every SwiftUI
    // body evaluation, causing unnecessary CPU work during animations and scrolling.
    @State private var visibleTasks: [TaskRecord] = []
    /// When smart sort is active, the same `visibleTasks` are also grouped
    /// into time-relevance buckets (Overdue / Today / This week / Later /
    /// No date) so the list reads as structured sections instead of one
    /// long scroll. Empty buckets are skipped. (UX assessment S1.)
    @State private var smartBuckets: [(bucket: TaskSmartSort.Bucket, tasks: [TaskRecord])] = []
    /// Completed within the last 24 hours — shown by default so the user can
    /// undo or reflect on recent wins.
    @State private var completedTasks: [TaskRecord] = []
    /// Completed more than 24 hours ago — folded behind a "Show older" link
    /// so finished work doesn't dominate the list. (UX assessment QW4.)
    @State private var olderCompletedTasks: [TaskRecord] = []
    @State private var showsOlderCompleted = false

    var body: some View {
        ZStack {
            List {
                if visibleTasks.isEmpty && completedTasks.isEmpty && olderCompletedTasks.isEmpty {
                    Section {
                        emptyState
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else if sortOrder == .smart && !smartBuckets.isEmpty {
                    // Smart sort renders one section per non-empty bucket so
                    // the user sees structure instead of one long flat list.
                    // Headers are rendered inline (as rows) instead of Section
                    // headers so they scroll with content rather than sticking
                    // to the top of the list as the user scrolls.
                    ForEach(smartBuckets, id: \.bucket.id) { group in
                        Section {
                            bucketHeader(group.bucket, count: group.tasks.count)
                            ForEach(group.tasks) { task in
                                TaskRowView(task: task) {
                                    taskPendingMove = task
                                } onOpenDetails: {
                                    selectedTask = task
                                }
                                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                    }
                    completedSection
                } else {
                    Section {
                        ForEach(visibleTasks) { task in
                            TaskRowView(task: task) {
                                taskPendingMove = task
                            } onOpenDetails: {
                                selectedTask = task
                            }
                            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }

                    completedSection
                }

                Section {
                    footer()
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            // Horizontal content margin keeps padding inside the scroll content
            // so the scroll indicator renders at the screen edge, not 10 pt in.
            .contentMargins(.horizontal, 10, for: .scrollContent)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismissKeyboard()
        }
        .sheet(item: $taskPendingMove) { task in
            MoveToFolderSheet(task: task)
                .presentationDragIndicator(.visible)
                .appSheetBackground()
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailSheet(task: task)
                .presentationDragIndicator(.visible)
                .appSheetBackground()
        }
        .alert("Clear completed tasks?", isPresented: $showsClearCompletedConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                captureService.clearCompletedTasks(filteredBy: selectedFolderID, in: modelContext)
            }
        } message: {
            Text("This permanently removes all completed tasks in the current view.")
        }
        // Recompute cached arrays only when their actual inputs change.
        // Previously these were computed properties that re-ran on every body evaluation
        // (including mid-animation frames), wasting CPU and causing scrolling stutter.
        //
        // Watching `allTasks` directly walked the entire `[TaskRecord]` array on every
        // change for Equatable comparison — O(N) per emission. Swap to a lightweight
        // (count + most-recent-update) digest so equality is O(1). (Medium bug.)
        .onAppear { recomputeTasks() }
        .onChange(of: tasksChangeDigest) { withAnimation(.snappy(duration: 0.3)) { recomputeTasks() } }
        .onChange(of: searchText) { recomputeTasks() }
        .onChange(of: sortOrder) { recomputeTasks() }
        .onChange(of: selectedFolderID) { recomputeTasks() }
    }

    /// Lightweight digest of `allTasks` so `onChange` doesn't walk every element
    /// for Equatable comparison. `(count, latest updatedAt)` is a cheap proxy:
    /// any insert/delete shifts count, any in-place mutation bumps updatedAt
    /// (TaskCaptureService writes `.updatedAt = .now` on every change).
    private var tasksChangeDigest: TasksDigest {
        // Walk once — same cost as Equatable on the array but bounded to two
        // scalars in @State so SwiftUI's diffing path is O(1).
        var latest: Date = .distantPast
        for task in allTasks where task.updatedAt > latest {
            latest = task.updatedAt
        }
        return TasksDigest(count: allTasks.count, latestUpdate: latest)
    }

    private struct TasksDigest: Equatable {
        let count: Int
        let latestUpdate: Date
    }

    // MARK: - Helpers

    private func isInActiveSection(_ task: TaskRecord) -> Bool {
        return task.status != .done
    }

    /// Recomputes the filtered and sorted task arrays and writes them to @State.
    private func recomputeTasks() {
        let trace = PerformanceTrace.beginInterval(
            PerformanceTrace.taskListRecompute,
            message: "InboxView.recomputeTasks begin"
        )
        defer {
            PerformanceTrace.endInterval(
                PerformanceTrace.taskListRecompute,
                trace,
                message: "InboxView.recomputeTasks end visible=\(visibleTasks.count) completed=\(completedTasks.count)"
            )
        }
        let inFolder = { (task: TaskRecord) in
            let folderMatches: Bool
            if let id = selectedFolderID {
                folderMatches = task.folderID == id
            } else if restrictToInbox {
                folderMatches = task.folderID == nil
            } else {
                folderMatches = true
            }
            return folderMatches && matchesSearch(task)
        }
        let activeTasks = allTasks.filter { task in
            isInActiveSection(task) && inFolder(task)
        }
        visibleTasks = sorted(activeTasks)
        // Bucketed view only matters for smart sort — other sorts get a flat list.
        smartBuckets = sortOrder == .smart ? TaskSmartSort.bucketed(activeTasks) : []
        var done = allTasks.filter { task in
            task.status == .done && inFolder(task)
        }
        done.sort { $0.updatedAt > $1.updatedAt }
        // Split completed into "recent (≤24h)" vs "older" so the list doesn't
        // get dominated by yesterday's wins. (UX assessment QW4.)
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let recencyAnchor: (TaskRecord) -> Date = { $0.completedAt ?? $0.updatedAt }
        completedTasks = done.filter { recencyAnchor($0) >= cutoff }
        olderCompletedTasks = done.filter { recencyAnchor($0) < cutoff }
    }

    private func matchesSearch(_ task: TaskRecord) -> Bool {
        guard !searchText.isEmpty else { return true }
        return task.title.localizedCaseInsensitiveContains(searchText) ||
               task.taskDescription.localizedCaseInsensitiveContains(searchText)
    }

    private func sorted(_ tasks: [TaskRecord]) -> [TaskRecord] {
        switch sortOrder {
        case .smart:
            return TaskSmartSort.sorted(tasks)
        case .newest:
            return tasks.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return tasks.sorted { $0.createdAt < $1.createdAt }
        case .alphabetical:
            return tasks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .dueDate:
            return tasks.sorted {
                switch ($0.dueDate, $1.dueDate) {
                case let (a?, b?): return a < b
                case (nil, _): return false
                case (_, nil): return true
                }
            }
        }
    }

    /// Section header for smart-sort buckets. Mirrors the colour-coded
    /// "control-center" feel: Overdue tinted red, Today tinted accent,
    /// the rest muted so the eye drops naturally to what matters.
    @ViewBuilder
    private func bucketHeader(_ bucket: TaskSmartSort.Bucket, count: Int) -> some View {
        let tint = bucketTint(bucket)
        HStack(spacing: 8) {
            Image(systemName: bucket.systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(bucket.title)
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(.primary)
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(tint.opacity(0.12), in: Capsule())
                }
                Text(bucket.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.mutedText)
            }
            Spacer()
        }
        .padding(.top, bucket == .overdue || bucket == .today ? 12 : 16)
        .padding(.bottom, 4)
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityAddTraits(.isHeader)
    }

    private func bucketTint(_ bucket: TaskSmartSort.Bucket) -> Color {
        switch bucket {
        case .overdue: return Color(red: 0.85, green: 0.30, blue: 0.25)
        case .today: return Color(red: 0.88, green: 0.55, blue: 0.20)
        case .thisWeek: return Color(red: 0.40, green: 0.56, blue: 0.85)
        case .later: return AppTheme.mutedText
        case .noDate: return AppTheme.mutedText.opacity(0.85)
        }
    }

    @ViewBuilder
    private var completedSection: some View {
        if !completedTasks.isEmpty || !olderCompletedTasks.isEmpty {
            Section {
                HStack {
                    Text("Recently completed")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(-0.1)
                        .foregroundStyle(AppTheme.mutedText)
                    Spacer()
                    Button("Clear all") {
                        showsClearCompletedConfirmation = true
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.85, green: 0.30, blue: 0.25))
                }
                .padding(.top, 14)
                .padding(.bottom, 4)
                .padding(.horizontal, 4)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityAddTraits(.isHeader)

                let visibleCompleted = showsOlderCompleted
                    ? (completedTasks + olderCompletedTasks)
                    : completedTasks

                // Tight list with dividers instead of card-per-item: removes the
                // big card backgrounds + stacked 2pt row insets that were producing
                // ~16pt of dead space between every completed row.
                ForEach(Array(visibleCompleted.enumerated()), id: \.element.id) { index, task in
                    completedRow(task)
                        .overlay(alignment: .bottom) {
                            if index < visibleCompleted.count - 1 {
                                Divider()
                                    .padding(.leading, 32)
                                    .opacity(0.5)
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                withAnimation(.snappy(duration: 0.22)) {
                                    captureService.toggleCompletion(task, in: modelContext)
                                }
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(Color.primary)
                        }
                        // Disable full-swipe on Delete in the completed list — a
                        // long horizontal swipe here was the leading source of
                        // mistaken deletes. (UX P6.)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                captureService.delete(task, in: modelContext)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if !olderCompletedTasks.isEmpty {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            showsOlderCompleted.toggle()
                        }
                    } label: {
                        Text(showsOlderCompleted
                             ? "Hide older"
                             : "Show \(olderCompletedTasks.count) older completed")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.mutedText)
                            .padding(.vertical, 8)
                            .padding(.leading, 32)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
    }

    /// Single row in the recently-completed list — no card background, no extra
    /// vertical padding, just a checkmark + strikethrough title. Dividers are
    /// added by the caller via overlay so they don't ride the swipe action.
    private func completedRow(_ task: TaskRecord) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.mutedText.opacity(0.7))
                .frame(width: 24, height: 24)
            Text(task.title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AppTheme.mutedText)
                .strikethrough(color: AppTheme.mutedText.opacity(0.45))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.22)) {
                captureService.toggleCompletion(task, in: modelContext)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: emptyStateIcon)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(emptyStateTint)
                .appIconButton(size: 48)

            Text(emptyStateTitle)
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.4)

            Text(emptyStateSubtitle)
                .font(.system(size: 14, weight: .medium))
                .tracking(-0.2)
                .foregroundStyle(AppTheme.mutedText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Empty-state copy varies by reason: searching, post-completion celebration,
    /// or first-launch onboarding nudge. Avoids the previous one-size copy that
    /// said "the inbox is clear" even when the user had cleared a busy day.
    private var emptyStateIcon: String {
        if !searchText.isEmpty { return "magnifyingglass" }
        if !olderCompletedTasks.isEmpty || !completedTasks.isEmpty {
            return "checkmark.seal.fill"
        }
        return "text.badge.plus"
    }

    private var emptyStateTint: Color {
        if !searchText.isEmpty { return AppTheme.mutedText }
        if !olderCompletedTasks.isEmpty || !completedTasks.isEmpty {
            return Color(red: 0.30, green: 0.65, blue: 0.45)
        }
        return AppTheme.mutedText
    }

    private var emptyStateTitle: String {
        if !searchText.isEmpty { return "No matching tasks." }
        if !olderCompletedTasks.isEmpty || !completedTasks.isEmpty {
            return "All clear."
        }
        return "Inbox is empty."
    }

    private var emptyStateSubtitle: String {
        if !searchText.isEmpty {
            return "Try a different search term or clear the filter."
        }
        if !completedTasks.isEmpty {
            return "Everything you wrapped up is right below."
        }
        if !olderCompletedTasks.isEmpty {
            return "Past wins are tucked away — tap + to capture the next thing."
        }
        return "Tap + to capture the first thing on your mind."
    }
}

extension InboxView where Footer == EmptyView {
    /// Convenience init for callers that don't need a scrolling footer.
    init(
        captureService: TaskCaptureService,
        selectedFolderID: UUID?,
        restrictToInbox: Bool = false,
        searchText: String = "",
        sortOrder: TaskSortOrder = .smart
    ) {
        self.init(
            captureService: captureService,
            selectedFolderID: selectedFolderID,
            restrictToInbox: restrictToInbox,
            searchText: searchText,
            sortOrder: sortOrder,
            footer: { EmptyView() }
        )
    }
}

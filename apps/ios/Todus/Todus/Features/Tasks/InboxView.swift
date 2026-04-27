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
    var sortOrder: TaskSortOrder = .newest

    /// Optional content rendered below the task list, scrolling together as one page.
    /// Used by the Tasks tab to surface the Folders grid at the bottom.
    @ViewBuilder var footer: () -> Footer

    // Cached derived arrays — recomputed only when inputs change (not on every render).
    // Computing filtered+sorted arrays in computed properties re-ran on every SwiftUI
    // body evaluation, causing unnecessary CPU work during animations and scrolling.
    @State private var visibleTasks: [TaskRecord] = []
    @State private var completedTasks: [TaskRecord] = []
    /// Sleeps until the next done-task exits the 5s grace window, then recomputes once.
    /// Replaces a 2 Hz `Timer.publish` that woke the main thread forever and contributed
    /// to perceived UI hangs.
    @State private var graceWindowRefreshTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            List {
                if visibleTasks.isEmpty && completedTasks.isEmpty {
                    Section {
                        emptyState
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
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

                    if !completedTasks.isEmpty {
                        Section {
                            ForEach(completedTasks) { task in
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppTheme.mutedText)
                                    Text(task.title)
                                        .font(.system(size: 14, weight: .medium))
                                        .tracking(-0.2)
                                        .foregroundStyle(AppTheme.mutedText)
                                        .strikethrough()
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
                                // Tap to restore a completed task back to .todo
                                .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.snappy(duration: 0.22)) {
                                            captureService.toggleCompletion(task, in: modelContext)
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
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        captureService.delete(task, in: modelContext)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        } header: {
                            HStack {
                                Text("Recently completed")
                                    .font(.system(size: 12, weight: .semibold))
                                    .tracking(-0.1)
                                    .textCase(nil)
                                    .foregroundStyle(AppTheme.mutedText)

                                Spacer()

                                Button("Clear") {
                                    showsClearCompletedConfirmation = true
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .textCase(nil)
                            }
                            .padding(.top, 16)
                            .padding(.bottom, 4)
                        }
                    }
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
        .onAppear { recomputeTasks() }
        .onDisappear { graceWindowRefreshTask?.cancel() }
        .onChange(of: allTasks) { recomputeTasks() }
        .onChange(of: searchText) { recomputeTasks() }
        .onChange(of: sortOrder) { recomputeTasks() }
        .onChange(of: selectedFolderID) { recomputeTasks() }
    }

    // MARK: - Helpers

    /// `true` when the task should appear in the main list (incomplete, or done but still inside the 5s window after `completedAt`).
    private func isInActiveSection(_ task: TaskRecord) -> Bool {
        if task.status != .done { return true }
        guard let at = task.completedAt else { return false }
        return Date() < at.addingTimeInterval(5)
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
        visibleTasks = sorted(allTasks.filter { task in
            isInActiveSection(task) && inFolder(task)
        })
        var done = allTasks.filter { task in
            task.status == .done && !isInActiveSection(task) && inFolder(task)
        }
        done.sort { $0.updatedAt > $1.updatedAt }
        completedTasks = done
        scheduleGraceWindowRefresh()
    }

    /// Schedules a single recompute for when the next done-task exits its 5s
    /// grace window. Skips entirely when no task is in the window — so the main
    /// thread is not woken up while the user is just reading their list.
    private func scheduleGraceWindowRefresh() {
        graceWindowRefreshTask?.cancel()
        let now = Date()
        let nextExit = allTasks.compactMap { task -> Date? in
            guard task.status == .done, let at = task.completedAt else { return nil }
            let exit = at.addingTimeInterval(5)
            return exit > now ? exit : nil
        }.min()
        guard let nextExit else { return }
        let delay = max(0.05, nextExit.timeIntervalSince(now))
        graceWindowRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            recomputeTasks()
        }
    }

    private func matchesSearch(_ task: TaskRecord) -> Bool {
        guard !searchText.isEmpty else { return true }
        return task.title.localizedCaseInsensitiveContains(searchText) ||
               task.taskDescription.localizedCaseInsensitiveContains(searchText)
    }

    private func sorted(_ tasks: [TaskRecord]) -> [TaskRecord] {
        switch sortOrder {
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: searchText.isEmpty ? "text.badge.plus" : "magnifyingglass")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
                .appIconButton(size: 48)

            Text(searchText.isEmpty ? "The inbox is clear." : "No matching tasks.")
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.4)

            Text(
                searchText.isEmpty
                    ? "Folders and other views can wait until you need them."
                    : "Try a different search term or clear the filter to get back to your full list."
            )
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
}

extension InboxView where Footer == EmptyView {
    /// Convenience init for callers that don't need a scrolling footer.
    init(
        captureService: TaskCaptureService,
        selectedFolderID: UUID?,
        restrictToInbox: Bool = false,
        searchText: String = "",
        sortOrder: TaskSortOrder = .newest
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

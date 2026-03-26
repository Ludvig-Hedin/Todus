import SwiftUI
import SwiftData

struct InboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]

    @State private var taskPendingMove: TaskRecord?
    @State private var selectedTask: TaskRecord?
    @State private var showsClearCompletedConfirmation = false

    /// Filter text from the home search bar
    var searchText: String = ""
    /// Sort order selected from the home sort menu
    var sortOrder: TaskSortOrder = .newest

    // Cached derived arrays — recomputed only when inputs change (not on every render).
    // Computing filtered+sorted arrays in computed properties re-ran on every SwiftUI
    // body evaluation, causing unnecessary CPU work during animations and scrolling.
    @State private var visibleTasks: [TaskRecord] = []
    @State private var completedTasks: [TaskRecord] = []

    var body: some View {
        ZStack {
            if visibleTasks.isEmpty && completedTasks.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(visibleTasks) { task in
                            TaskRowView(task: task) {
                                taskPendingMove = task
                            } onOpenDetails: {
                                selectedTask = task
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
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
                                .padding(.vertical, 12)
                                .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                // Tap to restore a completed task back to .todo
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.snappy(duration: 0.22)) {
                                        services.captureService.toggleCompletion(task, in: modelContext)
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        withAnimation(.snappy(duration: 0.22)) {
                                            services.captureService.toggleCompletion(task, in: modelContext)
                                        }
                                    } label: {
                                        Label("Restore", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(Color.blue)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        services.captureService.delete(task, in: modelContext)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        } header: {
                            HStack {
                                Text("Completed")
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
                            // Generous top padding matches the visual gap between active and completed sections
                            .padding(.top, 24)
                            .padding(.bottom, 4)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismissKeyboard()
        }
        .sheet(item: $taskPendingMove) { task in
            MoveToFolderSheet(task: task)
                .presentationDragIndicator(.visible)
                .presentationBackground(AppTheme.backgroundTop)
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailSheet(task: task)
                .presentationDragIndicator(.visible)
                .presentationBackground(AppTheme.backgroundTop)
        }
        .alert("Clear completed tasks?", isPresented: $showsClearCompletedConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                services.captureService.clearCompletedTasks(filteredBy: services.selectedFolderID, in: modelContext)
            }
        } message: {
            Text("This permanently removes all completed tasks in the current view.")
        }
        // Recompute cached arrays only when their actual inputs change.
        // Previously these were computed properties that re-ran on every body evaluation
        // (including mid-animation frames), wasting CPU and causing scrolling stutter.
        .onAppear { recomputeTasks() }
        .onChange(of: allTasks) { recomputeTasks() }
        .onChange(of: searchText) { recomputeTasks() }
        .onChange(of: sortOrder) { recomputeTasks() }
        .onChange(of: services.selectedFolderID) { recomputeTasks() }
    }

    // MARK: - Helpers

    /// Recomputes the filtered and sorted task arrays and writes them to @State.
    private func recomputeTasks() {
        visibleTasks = sorted(allTasks.filter { task in
            task.status != .done &&
            (services.selectedFolderID == nil || task.folderID == services.selectedFolderID) &&
            matchesSearch(task)
        })
        completedTasks = allTasks.filter { task in
            task.status == .done &&
            (services.selectedFolderID == nil || task.folderID == services.selectedFolderID) &&
            matchesSearch(task)
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
                    ? "Open the keyboard and drop your next thought straight in. Folders and board stay out of the way until you need them."
                    : "Try a different search term or clear the filter."
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

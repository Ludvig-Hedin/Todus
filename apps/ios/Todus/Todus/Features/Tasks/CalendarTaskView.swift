import SwiftUI
import SwiftData

/// Shows tasks grouped by due-date buckets (Today, Tomorrow, This Week, Later, No Date).
/// Used when the user selects the Calendar view mode.
struct CalendarTaskView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]

    @State private var selectedTask: TaskRecord?
    @State private var taskPendingMove: TaskRecord?

    var searchText: String = ""

    // MARK: - Bucketing

    private struct DateBucket: Identifiable {
        let id: String
        let label: String
        let tasks: [TaskRecord]
    }

    // Cached buckets — recomputed only when inputs change, not on every body evaluation.
    // Previously this was a computed property that re-ran during animations and scrolling.
    @State private var buckets: [DateBucket] = []

    private func recomputeBuckets() {
        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let tomorrowStart = cal.date(byAdding: .day, value: 1, to: todayStart)!
        let weekEnd = cal.date(byAdding: .day, value: 7, to: todayStart)!

        var today: [TaskRecord] = []
        var tomorrow: [TaskRecord] = []
        var thisWeek: [TaskRecord] = []
        var later: [TaskRecord] = []
        var noDate: [TaskRecord] = []

        for task in allTasks {
            guard
                task.status != .done,
                services.selectedFolderID == nil || task.folderID == services.selectedFolderID,
                matchesSearch(task)
            else { continue }

            guard let due = task.dueDate else {
                noDate.append(task)
                continue
            }
            let dueDay = cal.startOfDay(for: due)
            if dueDay <= todayStart {
                today.append(task)
            } else if dueDay == tomorrowStart {
                tomorrow.append(task)
            } else if dueDay < weekEnd {
                thisWeek.append(task)
            } else {
                later.append(task)
            }
        }

        var result: [DateBucket] = []
        if !today.isEmpty     { result.append(DateBucket(id: "today",    label: "Today",     tasks: today)) }
        if !tomorrow.isEmpty  { result.append(DateBucket(id: "tomorrow", label: "Tomorrow",  tasks: tomorrow)) }
        if !thisWeek.isEmpty  { result.append(DateBucket(id: "week",     label: "This Week", tasks: thisWeek)) }
        if !later.isEmpty     { result.append(DateBucket(id: "later",    label: "Later",     tasks: later)) }
        if !noDate.isEmpty    { result.append(DateBucket(id: "nodate",   label: "No Date",   tasks: noDate)) }
        buckets = result
    }

    // MARK: - Body

    var body: some View {
        Group {
            if buckets.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(buckets) { bucket in
                        Section {
                            ForEach(bucket.tasks) { task in
                                TaskRowView(task: task) {
                                    taskPendingMove = task
                                } onOpenDetails: {
                                    selectedTask = task
                                }
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        } header: {
                            Text(bucket.label)
                                .font(.system(size: 12, weight: .semibold))
                                .tracking(-0.1)
                                .textCase(nil)
                                .foregroundStyle(AppTheme.mutedText)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
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
            }
        }
        .onAppear { recomputeBuckets() }
        .onChange(of: allTasks) { recomputeBuckets() }
        .onChange(of: searchText) { recomputeBuckets() }
        .onChange(of: services.selectedFolderID) { recomputeBuckets() }
    }

    // MARK: - Helpers

    private func matchesSearch(_ task: TaskRecord) -> Bool {
        guard !searchText.isEmpty else { return true }
        return task.title.localizedCaseInsensitiveContains(searchText) ||
               task.taskDescription.localizedCaseInsensitiveContains(searchText)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: searchText.isEmpty ? "calendar.badge.checkmark" : "magnifyingglass")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
                .appIconButton(size: 48)
            Text(searchText.isEmpty ? "No upcoming tasks." : "No matching tasks.")
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.4)
            Text(
                searchText.isEmpty
                    ? "Tasks with a due date will appear here, grouped by when they're due."
                    : "Try a different search term."
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

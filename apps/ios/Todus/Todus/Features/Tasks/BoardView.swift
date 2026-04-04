import SwiftUI
import SwiftData

struct BoardView: View {
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]
    let captureService: TaskCaptureService
    let selectedFolderID: UUID?
    let searchText: String
    let sortOrder: TaskSortOrder
    @State private var selectedTask: TaskRecord?

    @State private var tasksByStatus: [TaskStatus: [TaskRecord]] = [:]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(TaskStatus.allCases) { status in
                        BoardColumnView(
                            captureService: captureService,
                            status: status,
                            tasks: tasksByStatus[status] ?? []
                        ) { task in
                            selectedTask = task
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .padding(.leading, 4)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $selectedTask) { task in
            TaskDetailSheet(task: task)
                .presentationDragIndicator(.visible)
                .presentationBackground(AppTheme.backgroundTop)
        }
        .onAppear { recomputeTasksByStatus() }
        .onChange(of: boardChangeDigest) { recomputeTasksByStatus() }
        .onChange(of: selectedFolderID) { recomputeTasksByStatus() }
        .onChange(of: searchText) { recomputeTasksByStatus() }
        .onChange(of: sortOrder) { recomputeTasksByStatus() }
    }

    private var boardChangeDigest: [BoardTaskDigest] {
        allTasks.map { task in
            BoardTaskDigest(
                id: task.id,
                status: task.status,
                folderID: task.folderID,
                updatedAt: task.updatedAt
            )
        }
    }

    private func recomputeTasksByStatus() {
        let trace = PerformanceTrace.beginInterval(
            PerformanceTrace.taskListRecompute,
            message: "BoardView.recomputeTasksByStatus begin"
        )
        defer {
            PerformanceTrace.endInterval(
                PerformanceTrace.taskListRecompute,
                trace,
                message: "BoardView.recomputeTasksByStatus end"
            )
        }
        var grouped: [TaskStatus: [TaskRecord]] = [:]
        for status in TaskStatus.allCases { grouped[status] = [] }
        for task in allTasks {
            guard
                !task.completed,
                selectedFolderID == nil || task.folderID == selectedFolderID,
                matchesSearch(task)
            else { continue }

            grouped[task.status, default: []].append(task)
        }

        for status in TaskStatus.allCases {
            grouped[status] = sortTasks(grouped[status] ?? [])
        }

        tasksByStatus = grouped
    }

    private func matchesSearch(_ task: TaskRecord) -> Bool {
        guard !searchText.isEmpty else { return true }
        return task.title.localizedCaseInsensitiveContains(searchText)
            || task.taskDescription.localizedCaseInsensitiveContains(searchText)
    }

    private func sortTasks(_ tasks: [TaskRecord]) -> [TaskRecord] {
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
                case (nil, nil): return $0.createdAt > $1.createdAt
                case (_, nil): return true
                case (nil, _): return false
                }
            }
        }
    }
}

private struct BoardTaskDigest: Equatable {
    let id: UUID
    let status: TaskStatus
    let folderID: UUID?
    let updatedAt: Date
}

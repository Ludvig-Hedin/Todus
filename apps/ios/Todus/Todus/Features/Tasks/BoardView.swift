import SwiftUI
import SwiftData

// Note: tasks within a column are intentionally unordered — their order is
// derived purely from `sortOrder` (Smart / Recent / Due / Alphabetical). Manual
// drag-to-reorder *within* a column is not supported because there is no
// persisted `boardPosition` field on `TaskRecord` to anchor a stable order
// across sync. Drag-and-drop *between* columns still works via the column-level
// `.dropDestination` that calls `setStatus`. Add a `boardPosition` column and
// reorder-mutation to the sync schema before enabling within-column reordering.
// (UX P8.)
struct BoardView: View {
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]
    let captureService: TaskCaptureService
    let selectedFolderID: UUID?
    var restrictToInbox: Bool = false
    let searchText: String
    let sortOrder: TaskSortOrder
    /// Top inset in points — passed by the parent to account for the pinned
    /// header height. Applied as `.padding(.top, topInset)` on the HStack so
    /// the board content starts below the header without the safeAreaInset gap
    /// that vertical scroll views absorb automatically but horizontal-only
    /// scroll views cannot (the gap would be permanent, not scroll-away-able).
    var topInset: CGFloat = 0
    @State private var selectedTask: TaskRecord?

    @State private var tasksByStatus: [TaskStatus: [TaskRecord]] = [:]

    var body: some View {
        GeometryReader { geo in
            // Effective board height = full geometry minus the header (topInset)
            // and minus the tab-bar overlay (~130pt). Columns must clear both so
            // their inner vertical ScrollView doesn't hide content behind chrome.
            let bottomReserve: CGFloat = 130
            let columnHeight = max(120, geo.size.height - topInset - bottomReserve)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(TaskStatus.allCases) { status in
                        BoardColumnView(
                            captureService: captureService,
                            status: status,
                            tasks: tasksByStatus[status] ?? []
                        ) { task in
                            selectedTask = task
                        }
                        .frame(height: columnHeight)
                    }
                }
                .padding(.top, topInset)
                .padding(.horizontal, 16)
                .padding(.bottom, bottomReserve)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailSheet(task: task)
                .presentationDragIndicator(.visible)
                .appSheetBackground()
        }
        .onAppear { recomputeTasksByStatus() }
        .onChange(of: boardChangeDigest) { recomputeTasksByStatus() }
        .onChange(of: selectedFolderID) { recomputeTasksByStatus() }
        .onChange(of: searchText) { recomputeTasksByStatus() }
        .onChange(of: sortOrder) { recomputeTasksByStatus() }
        .onChange(of: restrictToInbox) { recomputeTasksByStatus() }
    }

    private var boardChangeDigest: TasksDigest {
        // Sum term catches in-place sync updates whose updatedAt ≤ current max
        // (count + max alone left the board stale after multi-device sync).
        var latest: Date = .distantPast
        var sum: Double = 0
        for task in allTasks {
            if task.updatedAt > latest { latest = task.updatedAt }
            sum += task.updatedAt.timeIntervalSinceReferenceDate
        }
        return TasksDigest(count: allTasks.count, latestUpdate: latest, updateSum: sum)
    }

    private struct TasksDigest: Equatable {
        let count: Int
        let latestUpdate: Date
        let updateSum: Double
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
            let folderMatches: Bool
            if let id = selectedFolderID {
                folderMatches = task.folderID == id
            } else if restrictToInbox {
                folderMatches = task.folderID == nil
            } else {
                folderMatches = true
            }
            // Completed tasks belong in the Done column. Excluding them entirely
            // makes drag-to-Done look like deletion.
            guard folderMatches, matchesSearch(task) else { continue }
            if task.completed && task.status != .done { continue }

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
                case (nil, nil): return $0.createdAt > $1.createdAt
                case (_, nil): return true
                case (nil, _): return false
                }
            }
        }
    }
}


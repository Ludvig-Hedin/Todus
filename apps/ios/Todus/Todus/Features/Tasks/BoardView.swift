import SwiftUI
import SwiftData

struct BoardView: View {
    @Environment(AppServices.self) private var services
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]
    @State private var selectedTask: TaskRecord?

    // Cached tasks grouped by status — recomputed only when inputs change.
    // Previously filteredTasks(for:) was called 4x per body evaluation (once per status column).
    @State private var tasksByStatus: [TaskStatus: [TaskRecord]] = [:]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(TaskStatus.allCases) { status in
                    BoardColumnView(status: status, tasks: tasksByStatus[status] ?? []) { task in
                        selectedTask = task
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .scrollDismissesKeyboard(.interactively)
        .contentShape(Rectangle())
        .onTapGesture {
            dismissKeyboard()
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailSheet(task: task)
                .presentationDragIndicator(.visible)
                .presentationBackground(AppTheme.backgroundTop)
        }
        .onAppear { recomputeTasksByStatus() }
        .onChange(of: allTasks) { recomputeTasksByStatus() }
        .onChange(of: services.selectedFolderID) { recomputeTasksByStatus() }
        // SwiftData's @Query only triggers onChange when the array identity changes (insert/delete),
        // not when a property like `status` changes on an existing record. This signature captures
        // status values so the board re-groups when a task moves between columns.
        .onChange(of: taskChangeSignature) { recomputeTasksByStatus() }
    }

    /// Lightweight signature that changes when any task's status or folder assignment changes.
    /// Used to trigger recomputation even when SwiftData's @Query doesn't detect property mutations.
    private var taskChangeSignature: String {
        allTasks.map { "\($0.id)-\($0.status.rawValue)-\($0.folderID?.uuidString ?? "")" }.joined()
    }

    private func recomputeTasksByStatus() {
        var grouped: [TaskStatus: [TaskRecord]] = [:]
        for status in TaskStatus.allCases {
            grouped[status] = []
        }
        for task in allTasks {
            guard services.selectedFolderID == nil || task.folderID == services.selectedFolderID else { continue }
            grouped[task.status, default: []].append(task)
        }
        tasksByStatus = grouped
    }
}

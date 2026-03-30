import SwiftUI
import SwiftData

struct BoardView: View {
    @Environment(AppServices.self) private var services
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]
    @State private var selectedTask: TaskRecord?

    @State private var tasksByStatus: [TaskStatus: [TaskRecord]] = [:]

    var body: some View {
        // Both axes scroll: horizontal for columns, vertical for tall columns with many cards.
        // .fixedSize(vertical: true) on the HStack makes columns use their natural (ideal) height
        // instead of being clamped to the available screen height — which is what caused clipping.
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(TaskStatus.allCases) { status in
                    BoardColumnView(status: status, tasks: tasksByStatus[status] ?? []) { task in
                        selectedTask = task
                    }
                }
            }
            // horizontal: false → columns can still grow horizontally as needed
            // vertical: true   → HStack uses its ideal/natural height (tallest column drives height)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $selectedTask) { task in
            TaskDetailSheet(task: task)
                .presentationDragIndicator(.visible)
                .presentationBackground(AppTheme.backgroundTop)
        }
        .onAppear { recomputeTasksByStatus() }
        .onChange(of: taskChangeSignature) { recomputeTasksByStatus() }
        .onChange(of: services.selectedFolderID) { recomputeTasksByStatus() }
    }

    private var taskChangeSignature: String {
        allTasks
            .map { task in
                [
                    task.id.uuidString,
                    task.status.rawValue,
                    task.folderID ?? "nil"
                ].joined(separator: ":")
            }
            .joined(separator: "|")
    }

    private func recomputeTasksByStatus() {
        var grouped: [TaskStatus: [TaskRecord]] = [:]
        for status in TaskStatus.allCases { grouped[status] = [] }
        for task in allTasks {
            guard services.selectedFolderID == nil || task.folderID == services.selectedFolderID else { continue }
            grouped[task.status, default: []].append(task)
        }
        tasksByStatus = grouped
    }
}

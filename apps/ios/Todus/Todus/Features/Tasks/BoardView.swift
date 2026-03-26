import SwiftUI
import SwiftData

struct BoardView: View {
    @Environment(AppServices.self) private var services
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]
    @State private var selectedTask: TaskRecord?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(TaskStatus.allCases) { status in
                    BoardColumnView(status: status, tasks: filteredTasks(for: status)) { task in
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
    }

    private func filteredTasks(for status: TaskStatus) -> [TaskRecord] {
        allTasks.filter { task in
            task.status == status && (services.selectedFolderID == nil || task.folderID == services.selectedFolderID)
        }
    }
}

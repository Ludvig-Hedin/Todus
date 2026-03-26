import SwiftUI
import SwiftData

/// Issue #10: Rebuild table view with proper column alignment.
/// Columns use fixed widths so the header and data rows match visually.
struct TaskTableView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]
    @State private var selectedTask: TaskRecord?

    private let statusColumnWidth: CGFloat = 64
    private let dueColumnWidth: CGFloat = 80

    private var visibleTasks: [TaskRecord] {
        allTasks.filter { task in
            services.selectedFolderID == nil || task.folderID == services.selectedFolderID
        }
    }

    var body: some View {
        List {
            headerRow

            ForEach(visibleTasks) { task in
                Button {
                    selectedTask = task
                } label: {
                    HStack(spacing: 0) {
                        // Title column — fills remaining width
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
                                .font(.system(size: 14, weight: .medium))
                                .tracking(-0.15)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            if !task.taskDescription.isEmpty {
                                Text(task.taskDescription)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AppTheme.mutedText)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Status column — fixed width, matches header
                        Text(task.status.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.mutedText)
                            .frame(width: statusColumnWidth, alignment: .trailing)

                        // Due column — fixed width, matches header
                        Group {
                            if let dueDate = task.dueDate {
                                Text(TaskDateFormatter.dueFormatter.string(from: dueDate))
                            } else {
                                Text("—")
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.mutedText)
                        .frame(width: dueColumnWidth, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                // Context menu for quick actions in table view
                .contextMenu {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            services.captureService.toggleCompletion(task, in: modelContext)
                        }
                    } label: {
                        Label(task.completed ? "Restore" : "Mark as Done", systemImage: task.completed ? "arrow.uturn.backward" : "checkmark.circle")
                    }

                    Button(role: .destructive) {
                        services.captureService.delete(task, in: modelContext)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Task")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Status")
                .frame(width: statusColumnWidth, alignment: .trailing)
            Text("Due")
                .frame(width: dueColumnWidth, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(AppTheme.mutedText)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

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

    // Cached visible tasks — recomputed only when inputs change, not on every body evaluation.
    @State private var visibleTasks: [TaskRecord] = []

    private func recomputeVisibleTasks() {
        visibleTasks = allTasks.filter { task in
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

                            // Same guard as TaskRowView: skip description if it mirrors the title
                            if !task.taskDescription.isEmpty && task.taskDescription != task.title {
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
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                // Match global 16pt side padding — replaces the outer .padding(.horizontal, 16)
                // that was applied in TasksTabView (which caused double-padding with list insets).
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
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
        .onAppear { recomputeVisibleTasks() }
        .onChange(of: allTasks) { recomputeVisibleTasks() }
        .onChange(of: services.selectedFolderID) { recomputeVisibleTasks() }
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
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        // Use same 16pt inset as data rows so the header aligns with the content
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

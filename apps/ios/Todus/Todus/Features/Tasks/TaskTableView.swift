import SwiftUI
import SwiftData

/// Issue #10: Rebuild table view with proper column alignment.
/// Columns use fixed widths so the header and data rows match visually.
struct TaskTableView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]
    @State private var selectedTask: TaskRecord?

    private let statusColumnWidth: CGFloat = 72
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
                        HStack(spacing: 8) {
                            // Completion checkbox
                            Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(task.completed ? task.status.tintColor : AppTheme.mutedText.opacity(0.6))

                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    // Priority indicator
                                    if task.priority != .none {
                                        Circle()
                                            .fill(priorityColor(task.priority))
                                            .frame(width: 5, height: 5)
                                    }

                                    Text(task.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .tracking(-0.15)
                                        .foregroundStyle(.primary.opacity(task.completed ? 0.45 : 0.88))
                                        .strikethrough(task.completed, color: .primary.opacity(0.2))
                                        .lineLimit(1)
                                }

                                // Description subtitle
                                if !task.taskDescription.isEmpty && task.taskDescription != task.title {
                                    Text(task.taskDescription)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(AppTheme.mutedText)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Status column — colored pill
                        statusPill(task.status)
                            .frame(width: statusColumnWidth, alignment: .trailing)

                        // Due column — color-coded date
                        Group {
                            if let dueDate = task.dueDate {
                                Text(TaskDateFormatter.dueFormatter.string(from: dueDate))
                                    .foregroundStyle(dueDateColor(dueDate))
                            } else {
                                Text("—")
                                    .foregroundStyle(AppTheme.mutedText.opacity(0.4))
                            }
                        }
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: dueColumnWidth, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
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

                    // Quick status change submenu
                    Menu {
                        ForEach(TaskStatus.allCases) { targetStatus in
                            if targetStatus != task.status {
                                Button {
                                    withAnimation(.snappy(duration: 0.22)) {
                                        services.captureService.setStatus(task, status: targetStatus, in: modelContext)
                                    }
                                } label: {
                                    Label(targetStatus.title, systemImage: targetStatus.systemImage)
                                }
                            }
                        }
                    } label: {
                        Label("Move to…", systemImage: "arrow.right.circle")
                    }

                    Divider()

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

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Task")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Status")
                .frame(width: statusColumnWidth, alignment: .trailing)
            Text("Due")
                .frame(width: dueColumnWidth, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .semibold))
        .tracking(0.3)
        .textCase(.uppercase)
        .foregroundStyle(AppTheme.mutedText)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(AppTheme.surfaceSecondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 0.5)
        )
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 6, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Status Pill

    /// Colored status pill — tinted bg + tinted text, matching column accent colors
    private func statusPill(_ status: TaskStatus) -> some View {
        HStack(spacing: 3) {
            Image(systemName: status.systemImage)
                .font(.system(size: 8, weight: .bold))
            Text(status.title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(-0.1)
        }
        .foregroundStyle(status.tintColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(status.tintColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(status.tintColor.opacity(0.12), lineWidth: 0.5)
        )
    }

    // MARK: - Helpers

    private func priorityColor(_ priority: AppTaskPriority) -> Color {
        switch priority {
        case .high:   return Color(red: 0.85, green: 0.30, blue: 0.25)
        case .medium: return Color(red: 0.88, green: 0.65, blue: 0.20)
        case .low:    return Color(red: 0.50, green: 0.60, blue: 0.70)
        default:      return AppTheme.mutedText
        }
    }

    private func dueDateColor(_ date: Date) -> Color {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return Color(red: 0.88, green: 0.65, blue: 0.20)
        } else if date < Date() {
            return Color(red: 0.85, green: 0.30, blue: 0.25)
        }
        return AppTheme.mutedText
    }
}

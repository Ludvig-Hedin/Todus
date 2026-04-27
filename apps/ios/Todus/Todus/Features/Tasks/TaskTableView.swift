import SwiftUI
import SwiftData

/// Issue #10: Rebuild table view with proper column alignment.
/// Columns use fixed widths so the header and data rows match visually.
struct TaskTableView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]
    let captureService: TaskCaptureService
    let selectedFolderID: UUID?
    var restrictToInbox: Bool = false
    let searchText: String
    let sortOrder: TaskSortOrder
    @State private var selectedTask: TaskRecord?
    @State private var pendingDeleteTask: TaskRecord?

    private let statusColumnWidth: CGFloat = 72
    private let dueColumnWidth: CGFloat = 80

    // Cached visible tasks — recomputed only when inputs change, not on every body evaluation.
    @State private var visibleTasks: [TaskRecord] = []

    private func recomputeVisibleTasks() {
        let trace = PerformanceTrace.beginInterval(
            PerformanceTrace.taskListRecompute,
            message: "TaskTableView.recomputeVisibleTasks begin"
        )
        defer {
            PerformanceTrace.endInterval(
                PerformanceTrace.taskListRecompute,
                trace,
                message: "TaskTableView.recomputeVisibleTasks end count=\(visibleTasks.count)"
            )
        }
        visibleTasks = allTasks.filter { task in
            let folderMatches: Bool
            if let id = selectedFolderID {
                folderMatches = task.folderID == id
            } else if restrictToInbox {
                folderMatches = task.folderID == nil
            } else {
                folderMatches = true
            }
            return !task.completed && folderMatches && matchesSearch(task)
        }
        visibleTasks = sortTasks(visibleTasks)
    }

    var body: some View {
        Group {
            if visibleTasks.isEmpty {
                emptyState
            } else {
                List {
                    headerRow

                    ForEach(visibleTasks) { task in
                        Button {
                            selectedTask = task
                        } label: {
                            HStack(spacing: 0) {
                                // Title column — fills remaining width
                                HStack(spacing: 8) {
                                    Image(systemName: "circle")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(AppTheme.mutedText.opacity(0.6))

                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack(spacing: 4) {
                                            if task.priority != .none {
                                                Circle()
                                                    .fill(priorityColor(task.priority))
                                                    .frame(width: 5, height: 5)
                                            }

                                            Text(task.title)
                                                .font(.system(size: 13, weight: .medium))
                                                .tracking(-0.15)
                                                .foregroundStyle(.primary.opacity(0.88))
                                                .lineLimit(1)
                                        }

                                        if !task.taskDescription.isEmpty && task.taskDescription != task.title {
                                            Text(task.taskDescription)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(AppTheme.mutedText)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                statusPill(task.status)
                                    .frame(width: statusColumnWidth, alignment: .trailing)

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
                        .contextMenu {
                            Button {
                                withAnimation(.snappy(duration: 0.22)) {
                                    captureService.toggleCompletion(task, in: modelContext)
                                }
                            } label: {
                                Label("Mark as Done", systemImage: "checkmark.circle")
                            }

                            Menu {
                                ForEach(TaskStatus.allCases) { targetStatus in
                                    if targetStatus != task.status {
                                        Button {
                                            withAnimation(.snappy(duration: 0.22)) {
                                                captureService.setStatus(task, status: targetStatus, in: modelContext)
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
                                pendingDeleteTask = task
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
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
                .appSheetBackground()
        }
        .alert(
            "Delete task?",
            isPresented: Binding(
                get: { pendingDeleteTask != nil },
                set: { if !$0 { pendingDeleteTask = nil } }
            ),
            presenting: pendingDeleteTask
        ) { task in
            Button("Delete", role: .destructive) {
                captureService.delete(task, in: modelContext)
                pendingDeleteTask = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteTask = nil
            }
        } message: { task in
            Text("Delete “\(task.title)”? This action can’t be undone.")
        }
        .onAppear { recomputeVisibleTasks() }
        .onChange(of: allTasks) { recomputeVisibleTasks() }
        .onChange(of: selectedFolderID) { recomputeVisibleTasks() }
        .onChange(of: searchText) { recomputeVisibleTasks() }
        .onChange(of: sortOrder) { recomputeVisibleTasks() }
        .onChange(of: restrictToInbox) { recomputeVisibleTasks() }
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
        .background(AppTheme.surfaceSecondary.opacity(0.6), in: RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
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
        .background(status.tintColor.opacity(0.10), in: RoundedRectangle(cornerRadius: AppTheme.Radius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.chip, style: .continuous)
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: searchText.isEmpty ? "tablecells" : "magnifyingglass")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
                .appIconButton(size: 44)
            Text(searchText.isEmpty ? "No visible tasks." : "No matching tasks.")
                .font(.system(size: 18, weight: .semibold))
            Text(searchText.isEmpty ? "Table view focuses on active work. Completed tasks stay in List." : "Try a different search term.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

import SwiftUI
import SwiftData
import UIKit

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
                ScrollView {
                    VStack(spacing: 0) {
                        headerRow

                        Divider().opacity(0.25)

                        LazyVStack(spacing: 0) {
                            ForEach(visibleTasks) { task in
                                tableRow(task)
                                if task.id != visibleTasks.last?.id {
                                    Divider()
                                        .padding(.leading, 16)
                                        .opacity(0.12)
                                }
                            }
                        }
                    }
                    .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 0.5)
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { dismissKeyboard() }
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
            Button("Cancel", role: .cancel) { pendingDeleteTask = nil }
        } message: { task in
            Text("Delete \"\(task.title)\"? This action can't be undone.")
        }
        .onAppear { recomputeVisibleTasks() }
        // Use a (count + latest update) digest instead of `allTasks` so SwiftUI's
        // change diff is O(1) instead of O(N). (Medium bug.)
        .onChange(of: tasksChangeDigest) { recomputeVisibleTasks() }
        .onChange(of: selectedFolderID) { recomputeVisibleTasks() }
        .onChange(of: searchText) { recomputeVisibleTasks() }
        .onChange(of: sortOrder) { recomputeVisibleTasks() }
        .onChange(of: restrictToInbox) { recomputeVisibleTasks() }
    }

    private var tasksChangeDigest: TasksDigest {
        // Sum term catches in-place sync updates whose updatedAt ≤ current max
        // (count + max alone left the list stale after multi-device sync).
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

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 0) {
            // Leading spacer matches the checkbox column width on data rows
            // so the "Task" header aligns with the title text. (UX P10.)
            Color.clear.frame(width: 30)
            Text("Task")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Status")
                .frame(width: 84, alignment: .leading)
            Text("Due")
                .frame(width: 72, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .tracking(0.4)
        .textCase(.uppercase)
        .foregroundStyle(AppTheme.mutedText)
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 7)
    }

    // MARK: - Table Row

    @State private var hoveringRow: UUID? = nil

    private func tableRow(_ task: TaskRecord) -> some View {
        HStack(spacing: 0) {
            // Leading checkbox column — lets users complete a row directly from
            // the table view, matching list / board parity. (UX P10.)
            Button {
                // Same tactile pattern as TaskRowView.toggleCheckbox — the table
                // was the only surface whose primary checkbox completed silently.
                let willBecomeDone = !task.completed
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(AppTheme.Motion.base) {
                    captureService.toggleCompletion(task, in: modelContext)
                }
                if willBecomeDone {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } label: {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(task.completed ? task.status.tintColor : AppTheme.subtleText)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.completed ? "Mark as incomplete" : "Mark as complete")

            // Inner status icon removed — TaskStatus.todo's symbol is `circle`,
            // which collided with the checkbox column to render as a double-circle.
            // The trailing Status pill already shows the same icon + label, so the
            // duplicate was pure noise.
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if task.priority != .none {
                        Circle()
                            .fill(priorityColor(task.priority))
                            .frame(width: 5, height: 5)
                    }
                    Text(task.title)
                        .font(.system(size: 15, weight: .medium))
                        .tracking(-0.15)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                if !task.taskDescription.isEmpty && task.taskDescription != task.title {
                    Text(task.taskDescription)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppTheme.mutedText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            statusPill(task.status)
                .frame(width: 84, alignment: .leading)

            Group {
                if let dueDate = task.dueDate {
                    Text(TaskDateFormatter.dueFormatter.string(from: dueDate))
                        .foregroundStyle(dueDateColor(dueDate))
                } else {
                    Text("—")
                        .foregroundStyle(AppTheme.mutedText.opacity(0.4))
                }
            }
            .font(.system(size: 12, weight: .medium))
            .frame(width: 72, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { selectedTask = task }
        .contextMenu {
            Button {
                selectedTask = task
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button {
                withAnimation(AppTheme.Motion.base) {
                    captureService.toggleCompletion(task, in: modelContext)
                }
            } label: {
                Label(task.completed ? "Mark as incomplete" : "Mark as Done", systemImage: "checkmark.circle")
            }

            Divider()

            Button {
                UIPasteboard.general.string = task.title
            } label: {
                Label("Copy title", systemImage: "doc.on.doc")
            }
            if !task.taskDescription.isEmpty && task.taskDescription != task.title {
                Button {
                    UIPasteboard.general.string = task.taskDescription
                } label: {
                    Label("Copy description", systemImage: "text.quote")
                }
            }
            Button {
                let box = task.completed ? "- [x]" : "- [ ]"
                UIPasteboard.general.string = "\(box) \(task.title)"
            } label: {
                Label("Copy as Markdown", systemImage: "checkmark.square")
            }
            Button {
                captureService.captureInStatus(
                    title: task.title,
                    status: task.status,
                    folder: task.folder,
                    in: modelContext
                )
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }

            Menu {
                ForEach(AppTaskPriority.allCases) { p in
                    Button {
                        guard p != task.priority else { return }
                        withAnimation(AppTheme.Motion.fast) {
                            task.priority = p
                            task.updatedAt = .now
                            task.syncState = .pendingUpload
                            try? modelContext.save()
                        }
                    } label: {
                        if p == task.priority {
                            Label(p.title, systemImage: "checkmark")
                        } else {
                            Text(p.title)
                        }
                    }
                }
            } label: {
                Label("Priority", systemImage: "flag")
            }

            Menu {
                ForEach(TaskStatus.allCases) { targetStatus in
                    if targetStatus != task.status {
                        Button {
                            withAnimation(AppTheme.Motion.base) {
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

    // MARK: - Status Pill

    private func statusPill(_ status: TaskStatus) -> some View {
        HStack(spacing: 3) {
            Image(systemName: status.systemImage)
                .font(.system(size: 9, weight: .bold))
            Text(status.title)
                .font(.system(size: 11, weight: .semibold))
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

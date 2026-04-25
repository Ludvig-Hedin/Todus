import SwiftUI
import SwiftData

fileprivate struct CalendarDateBucket: Identifiable {
    let id: String
    let label: String
    let subtitle: String
    let icon: String
    let tint: Color
    let tasks: [TaskRecord]
}

/// Shows tasks grouped by due-date buckets (Today, Tomorrow, This Week, Later, No Date).
/// Used when the user selects the Calendar view mode.
struct CalendarTaskView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]

    @State private var selectedTask: TaskRecord?
    @State private var taskPendingMove: TaskRecord?

    var searchText: String = ""
    var sortOrder: TaskSortOrder = .dueDate

    // MARK: - Bucketing

    // Cached buckets — recomputed only when inputs change, not on every body evaluation.
    @State private var buckets: [CalendarDateBucket] = []

    private func recomputeBuckets() {
        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        guard let tomorrowStart = cal.date(byAdding: .day, value: 1, to: todayStart),
              let weekEnd = cal.date(byAdding: .day, value: 7, to: todayStart) else { return }


        var today: [TaskRecord] = []
        var tomorrow: [TaskRecord] = []
        var thisWeek: [TaskRecord] = []
        var later: [TaskRecord] = []
        var noDate: [TaskRecord] = []

        for task in allTasks {
            guard
                task.status != .done,
                services.selectedFolderID == nil || task.folderID == services.selectedFolderID,
                matchesSearch(task)
            else { continue }

            guard let due = task.dueDate else {
                noDate.append(task)
                continue
            }
            let dueDay = cal.startOfDay(for: due)
            if dueDay <= todayStart {
                today.append(task)
            } else if dueDay == tomorrowStart {
                tomorrow.append(task)
            } else if dueDay < weekEnd {
                thisWeek.append(task)
            } else {
                later.append(task)
            }
        }

        var result: [CalendarDateBucket] = []
        // Bucket colors: warm red-orange for urgent → cool blue for distant → neutral for unscheduled
        if !today.isEmpty {
            result.append(CalendarDateBucket(id: "today", label: "Today", subtitle: "Needs attention first", icon: "sun.max.fill",
                                     tint: Color(red: 0.88, green: 0.50, blue: 0.20), tasks: sortTasks(today)))
        }
        if !tomorrow.isEmpty {
            result.append(CalendarDateBucket(id: "tomorrow", label: "Tomorrow", subtitle: "Coming up next", icon: "sunrise.fill",
                                     tint: Color(red: 0.75, green: 0.62, blue: 0.30), tasks: sortTasks(tomorrow)))
        }
        if !thisWeek.isEmpty {
            result.append(CalendarDateBucket(id: "week", label: "This Week", subtitle: "Plan the week ahead", icon: "calendar",
                                     tint: Color(red: 0.40, green: 0.56, blue: 0.85), tasks: sortTasks(thisWeek)))
        }
        if !later.isEmpty {
            result.append(CalendarDateBucket(id: "later", label: "Later", subtitle: "Longer-term work", icon: "calendar.badge.clock",
                                     tint: Color(red: 0.55, green: 0.55, blue: 0.60), tasks: sortTasks(later)))
        }
        if !noDate.isEmpty {
            result.append(CalendarDateBucket(id: "nodate", label: "No Date", subtitle: "Needs a planned time", icon: "calendar.badge.minus",
                                     tint: Color(red: 0.50, green: 0.50, blue: 0.52), tasks: sortTasks(noDate)))
        }
        buckets = result
    }

    // MARK: - Body

    var body: some View {
        Group {
            if buckets.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(buckets) { bucket in
                            VStack(alignment: .leading, spacing: 10) {
                                bucketHeader(bucket)

                                VStack(spacing: 8) {
                                    ForEach(bucket.tasks) { task in
                                        CalendarTaskCard(task: task, bucket: bucket) {
                                            taskPendingMove = task
                                        } onOpenDetails: {
                                            selectedTask = task
                                        }
                                    }
                                }
                                .padding(.leading, 14)
                            }
                        }
                    }
                    .padding(.vertical, 10)
                }
                .scrollDismissesKeyboard(.interactively)
                .sheet(item: $taskPendingMove) { task in
                    MoveToFolderSheet(task: task)
                        .presentationDragIndicator(.visible)
                        .appSheetBackground()
                }
                .sheet(item: $selectedTask) { task in
                    TaskDetailSheet(task: task)
                        .presentationDragIndicator(.visible)
                        .appSheetBackground()
                }
            }
        }
        .onAppear { recomputeBuckets() }
        .onChange(of: allTasks) { recomputeBuckets() }
        .onChange(of: searchText) { recomputeBuckets() }
        .onChange(of: sortOrder) { recomputeBuckets() }
        .onChange(of: services.selectedFolderID) { recomputeBuckets() }
    }

    // MARK: - Bucket Header

    private func bucketHeader(_ bucket: CalendarDateBucket) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(bucket.label)
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.25)
                .foregroundStyle(.primary)

            Text(bucket.subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)

            Spacer()

            Text("\(bucket.tasks.count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(bucket.tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(bucket.tint.opacity(0.10), in: Capsule())
        }
    }

    // MARK: - Helpers

    private func matchesSearch(_ task: TaskRecord) -> Bool {
        guard !searchText.isEmpty else { return true }
        return task.title.localizedCaseInsensitiveContains(searchText) ||
               task.taskDescription.localizedCaseInsensitiveContains(searchText)
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
            Image(systemName: searchText.isEmpty ? "calendar.badge.clock" : "magnifyingglass")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
                .appIconButton(size: 48)
            Text(searchText.isEmpty ? "No upcoming tasks." : "No matching tasks.")
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.4)
            Text(
                searchText.isEmpty
                    ? "Tasks with dates will appear in order: today, tomorrow, this week, then later."
                    : "Try a different search term."
            )
            .font(.system(size: 14, weight: .medium))
            .tracking(-0.2)
            .foregroundStyle(AppTheme.mutedText)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CalendarTaskCard: View {
    let task: TaskRecord
    let bucket: CalendarDateBucket
    let onMoveRequested: () -> Void
    let onOpenDetails: () -> Void

    var body: some View {
        Button {
            onOpenDetails()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 4) {
                    Circle()
                        .fill(bucket.tint)
                        .frame(width: 8, height: 8)

                    Rectangle()
                        .fill(bucket.tint.opacity(0.18))
                        .frame(width: 2)
                }
                .frame(width: 12)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(task.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let dueDate = task.dueDate {
                            Text(TaskDateFormatter.dueFormatter.string(from: dueDate))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(bucket.tint)
                        }
                    }

                    HStack(spacing: 6) {
                        if !task.taskDescription.isEmpty && task.taskDescription != task.title {
                            Text(task.taskDescription)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppTheme.mutedText)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 6) {
                        CalendarMetaPill(
                            text: task.status.title,
                            systemImage: task.status.systemImage,
                            tint: task.status.tintColor
                        )

                        if task.priority != .none {
                            CalendarMetaPill(
                                text: task.priority.title,
                                systemImage: "flag.fill",
                                tint: priorityColor(task.priority)
                            )
                        }

                        if let folder = task.folder {
                            CalendarMetaPill(
                                text: folder.name,
                                systemImage: "folder",
                                tint: AppTheme.mutedText
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onMoveRequested()
            } label: {
                Label("Move", systemImage: "folder")
            }
        }
    }

    private func priorityColor(_ priority: AppTaskPriority) -> Color {
        switch priority {
        case .high:   return Color(red: 0.85, green: 0.30, blue: 0.25)
        case .medium: return Color(red: 0.88, green: 0.65, blue: 0.20)
        case .low:    return Color(red: 0.50, green: 0.60, blue: 0.70)
        default:      return AppTheme.mutedText
        }
    }
}

private struct CalendarMetaPill: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint.opacity(0.9))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(AppTheme.surfaceSecondary.opacity(0.7), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(AppTheme.cardBorder, lineWidth: 0.75)
            )
    }
}

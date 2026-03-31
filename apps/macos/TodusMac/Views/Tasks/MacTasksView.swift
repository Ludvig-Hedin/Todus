import SwiftUI
import SwiftData

/// Tasks page — list view with search, sort, folder filter, and view mode toggle.
/// Desktop-optimized: denser rows, hover states, keyboard-friendly.
struct MacTasksView: View {
    @Environment(MacAppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskRecord.createdAt, order: .reverse) private var allTasks: [TaskRecord]
    @Query(sort: \FolderRecord.createdAt) private var folders: [FolderRecord]

    @State private var searchText = ""
    @State private var sortOrder: TaskSortOrder = .newest
    @State private var selectedFolderID: UUID? = nil
    @State private var viewMode: TaskViewMode = .list
    @State private var selectedTask: TaskRecord? = nil
    @State private var visibleTasks: [TaskRecord] = []
    @State private var completedTasks: [TaskRecord] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toolbar: view mode + search + sort
            toolbar
                .padding(.bottom, MacTheme.spacing12)

            // Folder strip
            if !folders.isEmpty {
                folderStrip
                    .padding(.bottom, MacTheme.spacing12)
            }

            // Task list
            if visibleTasks.isEmpty && completedTasks.isEmpty {
                emptyState
            } else {
                taskContent
            }
        }
        .onAppear { recomputeTasks() }
        .task {
            await services.syncSharedFolders(in: modelContext)
        }
        .onChange(of: allTasks) { recomputeTasks() }
        .onChange(of: searchText) { recomputeTasks() }
        .onChange(of: sortOrder) { recomputeTasks() }
        .onChange(of: selectedFolderID) { recomputeTasks() }
        .sheet(item: $selectedTask) { task in
            MacTaskDetailSheet(task: task)
                .frame(minWidth: 420, minHeight: 320)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: MacTheme.spacing8) {
            // View mode picker
            viewModePicker

            Spacer()

            // Search field
            HStack(spacing: MacTheme.spacing6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MacTheme.mutedText)

                TextField("Search tasks...", text: $searchText)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .frame(maxWidth: 200)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(MacTheme.mutedText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, MacTheme.spacing8)
            .padding(.vertical, MacTheme.spacing6)
            .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )

            // Sort menu
            Menu {
                ForEach(TaskSortOrder.allCases) { order in
                    Button {
                        sortOrder = order
                    } label: {
                        Label(order.title, systemImage: sortOrder == order ? "checkmark" : order.systemImage)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MacTheme.mutedText)
                    .frame(width: 28, height: 28)
                    .background(MacTheme.surfaceCard, in: Circle())
                    .overlay(Circle().stroke(MacTheme.cardBorder, lineWidth: 0.5))
            }
            .menuStyle(.borderlessButton)
            .tint(Color.primary.opacity(0.7))
            .frame(width: 28)
        }
    }

    private var viewModePicker: some View {
        HStack(spacing: 1) {
            ForEach(TaskViewMode.allCases) { mode in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        viewMode = mode
                    }
                } label: {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(viewMode == mode ? MacTheme.textPrimary : MacTheme.mutedText)
                        .frame(width: 30, height: 24)
                        .background(
                            viewMode == mode
                                ? MacTheme.surfaceHover
                                : Color.clear,
                            in: Capsule(style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Folder Strip

    private var folderStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MacTheme.spacing4) {
                folderPill(name: "All", isSelected: selectedFolderID == nil) {
                    selectedFolderID = nil
                }

                ForEach(folders) { folder in
                    folderPill(name: folder.name, isSelected: selectedFolderID == folder.id) {
                        selectedFolderID = folder.id
                    }
                }
            }
        }
    }

    private func folderPill(name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? MacTheme.accent : MacTheme.textSecondary)
                .padding(.horizontal, MacTheme.spacing12)
                .padding(.vertical, MacTheme.spacing4)
                .background(
                    isSelected ? MacTheme.accent.opacity(0.1) : MacTheme.surfaceCard,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? MacTheme.accent.opacity(0.2) : MacTheme.cardBorder, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Task Content

    private var taskContent: some View {
        Group {
            switch viewMode {
            case .list:
                listView
            case .board:
                boardView
            case .table:
                tableView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - List View

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: MacTheme.spacing4) {
                ForEach(visibleTasks) { task in
                    MacTaskRow(task: task, onSelect: { selectedTask = task })
                }

                if !completedTasks.isEmpty {
                    completedSection
                }
            }
        }
    }

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: MacTheme.spacing4) {
            HStack {
                Text("COMPLETED")
                    .font(MacTheme.sectionHeaderFont())
                    .foregroundStyle(MacTheme.mutedText)
                    .tracking(0.8)
                Spacer()
                Text("\(completedTasks.count)")
                    .font(MacTheme.metaFont())
                    .foregroundStyle(MacTheme.mutedText)
            }
            .padding(.top, MacTheme.spacing16)
            .padding(.bottom, MacTheme.spacing4)

            ForEach(completedTasks) { task in
                HStack(spacing: MacTheme.spacing8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(MacTheme.mutedText)
                    Text(task.title)
                        .font(MacTheme.cardTitleFont())
                        .foregroundStyle(MacTheme.mutedText)
                        .strikethrough()
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, MacTheme.spacing12)
                .padding(.vertical, MacTheme.spacing6)
                .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
            }
        }
    }

    // MARK: - Board View (Kanban)

    private var boardView: some View {
        HStack(alignment: .top, spacing: MacTheme.spacing12) {
            ForEach(TaskStatus.allCases) { status in
                boardColumn(status: status)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func boardColumn(status: TaskStatus) -> some View {
        let tasks = visibleTasks.filter { $0.status == status }

        return VStack(alignment: .leading, spacing: MacTheme.spacing8) {
            HStack(spacing: MacTheme.spacing6) {
                Image(systemName: status.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(status.tintColor)

                Text(status.title.uppercased())
                    .font(MacTheme.sectionHeaderFont())
                    .foregroundStyle(MacTheme.mutedText)
                    .tracking(0.8)

                if !tasks.isEmpty {
                    Text("\(tasks.count)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(MacTheme.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(MacTheme.badgeSurface, in: RoundedRectangle(cornerRadius: MacTheme.pillRadius))
                }

                Spacer()
            }
            .padding(.bottom, MacTheme.spacing4)

            ScrollView {
                LazyVStack(spacing: MacTheme.spacing4) {
                    ForEach(tasks) { task in
                        MacTaskRow(task: task, onSelect: { selectedTask = task })
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(MacTheme.spacing12)
        .background(MacTheme.emptyStateSurface, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Table View

    private var tableView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Table header
                HStack(spacing: 0) {
                    Text("Task")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Status")
                        .frame(width: 80, alignment: .leading)
                    Text("Priority")
                        .frame(width: 80, alignment: .leading)
                    Text("Due Date")
                        .frame(width: 120, alignment: .leading)
                    Text("Folder")
                        .frame(width: 100, alignment: .leading)
                }
                .font(MacTheme.sectionHeaderFont())
                .foregroundStyle(MacTheme.mutedText)
                .tracking(0.5)
                .padding(.horizontal, MacTheme.spacing12)
                .padding(.vertical, MacTheme.spacing8)

                Divider().opacity(0.3)

                LazyVStack(spacing: 0) {
                    ForEach(visibleTasks) { task in
                        tableRow(task)
                        Divider().opacity(0.15)
                    }
                }
            }
            .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }

    @State private var hoveringTableRow: UUID? = nil

    private func tableRow(_ task: TaskRecord) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: MacTheme.spacing6) {
                Image(systemName: task.status.systemImage)
                    .font(.system(size: 11))
                    .foregroundStyle(task.status.tintColor)
                Text(task.title)
                    .font(MacTheme.cardTitleFont())
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(task.status.title)
                .font(MacTheme.cardSubtitleFont())
                .foregroundStyle(task.status.tintColor)
                .frame(width: 80, alignment: .leading)

            Text(task.priority == .none ? "—" : task.priority.title)
                .font(MacTheme.cardSubtitleFont())
                .foregroundStyle(task.priority == .none ? MacTheme.mutedText : priorityColor(task.priority))
                .frame(width: 80, alignment: .leading)

            Text(task.dueDate != nil ? TaskDateFormatter.shortDate.string(from: task.dueDate!) : "—")
                .font(MacTheme.cardSubtitleFont())
                .foregroundStyle(task.dueDate != nil ? dueDateColor(task.dueDate!) : MacTheme.mutedText)
                .frame(width: 120, alignment: .leading)

            Text(task.folder?.name ?? "—")
                .font(MacTheme.cardSubtitleFont())
                .foregroundStyle(MacTheme.mutedText)
                .frame(width: 100, alignment: .leading)
        }
        .padding(.horizontal, MacTheme.spacing12)
        .padding(.vertical, MacTheme.spacing6)
        .background(hoveringTableRow == task.id ? MacTheme.surfaceHover : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selectedTask = task }
        .onHover { hovering in
            hoveringTableRow = hovering ? task.id : nil
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: MacTheme.spacing12) {
            Spacer()
            Image(systemName: searchText.isEmpty ? "checkmark.circle" : "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(MacTheme.mutedText.opacity(0.5))

            Text(searchText.isEmpty ? "No tasks yet" : "No matching tasks")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(MacTheme.textSecondary)

            Text(searchText.isEmpty ? "Tasks you create will appear here." : "Try a different search term.")
                .font(MacTheme.cardSubtitleFont())
                .foregroundStyle(MacTheme.mutedText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func recomputeTasks() {
        visibleTasks = sorted(allTasks.filter { task in
            task.status != .done &&
            (selectedFolderID == nil || task.folderID == selectedFolderID) &&
            matchesSearch(task)
        })
        completedTasks = allTasks.filter { task in
            task.status == .done &&
            (selectedFolderID == nil || task.folderID == selectedFolderID) &&
            matchesSearch(task)
        }
    }

    private func matchesSearch(_ task: TaskRecord) -> Bool {
        guard !searchText.isEmpty else { return true }
        return task.title.localizedCaseInsensitiveContains(searchText) ||
               task.taskDescription.localizedCaseInsensitiveContains(searchText)
    }

    private func sorted(_ tasks: [TaskRecord]) -> [TaskRecord] {
        switch sortOrder {
        case .newest:       return tasks.sorted { $0.createdAt > $1.createdAt }
        case .oldest:       return tasks.sorted { $0.createdAt < $1.createdAt }
        case .alphabetical: return tasks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .dueDate:
            return tasks.sorted {
                switch ($0.dueDate, $1.dueDate) {
                case let (a?, b?): return a < b
                case (nil, _): return false
                case (_, nil): return true
                }
            }
        }
    }

    private func dueDateColor(_ date: Date) -> Color {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return Color(red: 0.88, green: 0.65, blue: 0.20) }
        if date < Date() { return Color(red: 0.85, green: 0.30, blue: 0.25) }
        return MacTheme.textSecondary
    }

    private func priorityColor(_ priority: AppTaskPriority) -> Color {
        switch priority {
        case .high:   return Color(red: 0.85, green: 0.30, blue: 0.25)
        case .medium: return Color(red: 0.88, green: 0.65, blue: 0.20)
        case .low:    return Color(red: 0.50, green: 0.60, blue: 0.70)
        default:      return MacTheme.mutedText
        }
    }
}

// MARK: - Task Row Component

/// A single task row for the list and board views — desktop-optimized with hover states.
struct MacTaskRow: View {
    let task: TaskRecord
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: MacTheme.spacing8) {
                Image(systemName: task.status.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(task.completed ? MacTheme.mutedText : task.status.tintColor)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(MacTheme.cardTitleFont())
                        .foregroundStyle(task.completed ? MacTheme.mutedText : MacTheme.textPrimary)
                        .strikethrough(task.completed)
                        .lineLimit(1)

                    // Metadata row
                    HStack(spacing: MacTheme.spacing4) {
                        if let dueDate = task.dueDate {
                            metaTag(
                                text: TaskDateFormatter.shortDate.string(from: dueDate),
                                icon: "calendar",
                                color: dueDateColor(dueDate)
                            )
                        }
                        if let folder = task.folder {
                            metaTag(text: folder.name, icon: "folder", color: MacTheme.mutedText)
                        }
                        if task.priority != .none {
                            metaTag(text: task.priority.title, icon: "flag.fill", color: priorityColor(task.priority))
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, MacTheme.spacing12)
            .padding(.vertical, MacTheme.spacing8)
            .background(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .fill(isHovered ? MacTheme.surfaceHover : MacTheme.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private func metaTag(text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: MacTheme.pillRadius))
    }

    private func dueDateColor(_ date: Date) -> Color {
        if Calendar.current.isDateInToday(date) { return Color(red: 0.88, green: 0.65, blue: 0.20) }
        if date < Date() { return Color(red: 0.85, green: 0.30, blue: 0.25) }
        return MacTheme.mutedText
    }

    private func priorityColor(_ priority: AppTaskPriority) -> Color {
        switch priority {
        case .high:   return Color(red: 0.85, green: 0.30, blue: 0.25)
        case .medium: return Color(red: 0.88, green: 0.65, blue: 0.20)
        case .low:    return Color(red: 0.50, green: 0.60, blue: 0.70)
        default:      return MacTheme.mutedText
        }
    }
}

// MARK: - Task Detail Sheet

/// Task detail sheet for viewing/editing a single task on macOS.
struct MacTaskDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let task: TaskRecord

    @State private var editedTitle: String = ""
    @State private var editedDescription: String = ""
    @State private var editedStatus: TaskStatus = .todo
    @State private var editedPriority: AppTaskPriority = .none
    @State private var editedDueDate: Date? = nil
    @State private var hasDueDate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Task Details")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Spacer()
                Button("Done") {
                    saveChanges()
                    dismiss()
                }
                .font(.system(size: 13, weight: .medium))
            }
            .padding(MacTheme.spacing16)

            Divider().opacity(0.3)

            ScrollView {
                VStack(alignment: .leading, spacing: MacTheme.spacing16) {
                    // Title
                    VStack(alignment: .leading, spacing: MacTheme.spacing4) {
                        Text("TITLE")
                            .font(MacTheme.sectionHeaderFont())
                            .foregroundStyle(MacTheme.mutedText)
                            .tracking(0.8)
                        TextField("Task title", text: $editedTitle)
                            .font(.system(size: 14))
                            .textFieldStyle(.plain)
                            .padding(MacTheme.spacing8)
                            .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius))
                            .overlay(RoundedRectangle(cornerRadius: MacTheme.buttonRadius).stroke(MacTheme.cardBorder, lineWidth: 0.5))
                    }

                    // Description
                    VStack(alignment: .leading, spacing: MacTheme.spacing4) {
                        Text("DESCRIPTION")
                            .font(MacTheme.sectionHeaderFont())
                            .foregroundStyle(MacTheme.mutedText)
                            .tracking(0.8)
                        TextEditor(text: $editedDescription)
                            .font(.system(size: 13))
                            .frame(minHeight: 60)
                            .padding(MacTheme.spacing4)
                            .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius))
                            .overlay(RoundedRectangle(cornerRadius: MacTheme.buttonRadius).stroke(MacTheme.cardBorder, lineWidth: 0.5))
                            .scrollContentBackground(.hidden)
                    }

                    // Status + Priority row
                    HStack(spacing: MacTheme.spacing16) {
                        VStack(alignment: .leading, spacing: MacTheme.spacing4) {
                            Text("STATUS")
                                .font(MacTheme.sectionHeaderFont())
                                .foregroundStyle(MacTheme.mutedText)
                                .tracking(0.8)
                            Picker("Status", selection: $editedStatus) {
                                ForEach(TaskStatus.allCases) { s in
                                    Text(s.title).tag(s)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        VStack(alignment: .leading, spacing: MacTheme.spacing4) {
                            Text("PRIORITY")
                                .font(MacTheme.sectionHeaderFont())
                                .foregroundStyle(MacTheme.mutedText)
                                .tracking(0.8)
                            Picker("Priority", selection: $editedPriority) {
                                ForEach(AppTaskPriority.allCases) { p in
                                    Text(p.title).tag(p)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }

                    // Due date
                    VStack(alignment: .leading, spacing: MacTheme.spacing4) {
                        HStack {
                            Text("DUE DATE")
                                .font(MacTheme.sectionHeaderFont())
                                .foregroundStyle(MacTheme.mutedText)
                                .tracking(0.8)
                            Spacer()
                            Toggle("", isOn: $hasDueDate)
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                        }
                        if hasDueDate {
                            DatePicker("", selection: Binding(
                                get: { editedDueDate ?? Date() },
                                set: { editedDueDate = $0 }
                            ))
                            .labelsHidden()
                            .datePickerStyle(.field)
                        }
                    }

                    // Metadata
                    if let folder = task.folder {
                        HStack(spacing: MacTheme.spacing6) {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                                .foregroundStyle(MacTheme.mutedText)
                            Text(folder.name)
                                .font(MacTheme.cardSubtitleFont())
                                .foregroundStyle(MacTheme.textSecondary)
                        }
                    }

                    HStack(spacing: MacTheme.spacing6) {
                        Text("Created")
                            .font(MacTheme.cardSubtitleFont())
                            .foregroundStyle(MacTheme.mutedText)
                        Text(task.createdAt, format: .dateTime.month().day().year().hour().minute())
                            .font(MacTheme.cardSubtitleFont())
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                }
                .padding(MacTheme.spacing16)
            }
        }
        .onAppear {
            editedTitle = task.title
            editedDescription = task.taskDescription
            editedStatus = task.status
            editedPriority = task.priority
            editedDueDate = task.dueDate
            hasDueDate = task.dueDate != nil
        }
    }

    private func saveChanges() {
        task.title = editedTitle
        task.taskDescription = editedDescription
        task.status = editedStatus
        task.priority = editedPriority
        task.dueDate = hasDueDate ? editedDueDate : nil
        task.updatedAt = .now
        try? modelContext.save()
    }
}

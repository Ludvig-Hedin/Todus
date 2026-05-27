import SwiftUI
import SwiftData

/// Lets the user add one or more items of any supported type to a folder.
/// Each picker supports multi-select, search, and type-specific filters.
struct AddToFolderSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let folder: FolderRecord
    var onAdded: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            List {
                Section("Add to \(folder.name)") {
                    NavigationLink {
                        TaskFolderPicker(folder: folder) { onAdded?(); dismiss() }
                    } label: {
                        rowLabel(icon: "checklist", title: "Task", subtitle: "Move an existing task here")
                    }
                    NavigationLink {
                        EmailFolderPicker(folder: folder) { onAdded?(); dismiss() }
                    } label: {
                        rowLabel(icon: "envelope.fill", title: "Email", subtitle: "Pin an email thread")
                    }
                    NavigationLink {
                        ChatFolderPicker(folder: folder) { onAdded?(); dismiss() }
                    } label: {
                        rowLabel(icon: "bubble.left.fill", title: "Chat", subtitle: "Save an AI conversation")
                    }
                    NavigationLink {
                        EventFolderPicker(folder: folder) { onAdded?(); dismiss() }
                    } label: {
                        rowLabel(icon: "calendar", title: "Event", subtitle: "Reference a calendar event")
                    }
                    NavigationLink {
                        DocFolderPicker(folder: folder) { onAdded?(); dismiss() }
                    } label: {
                        rowLabel(icon: "doc.text", title: "Doc", subtitle: "Attach a document")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.sheetBackground)
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func rowLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.subtleText)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.surfaceSecondary)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(subtitle).font(.system(size: 11, weight: .medium)).foregroundStyle(AppTheme.mutedText)
            }
        }
    }
}

// MARK: - Shared helpers

private func filterChipStyle(isSelected: Bool) -> some ShapeStyle {
    isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : AnyShapeStyle(AppTheme.surfaceSecondary)
}

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor.opacity(0.15) : AppTheme.surfaceSecondary)
                )
                .foregroundStyle(isSelected ? Color.accentColor : AppTheme.subtleText)
        }
        .buttonStyle(.plain)
    }
}

private struct AddButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Add \(count) \(count == 1 ? "item" : "items")")
                .font(.system(size: 14, weight: .semibold))
        }
    }
}

// MARK: - Task picker

private struct TaskFolderPicker: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Query(sort: \TaskRecord.updatedAt, order: .reverse) private var allTasks: [TaskRecord]

    let folder: FolderRecord
    let onAdded: () -> Void

    @State private var searchText = ""
    @State private var selectedIDs = Set<UUID>()
    @State private var statusFilter: TaskStatus? = nil

    private var candidates: [TaskRecord] {
        allTasks.filter { $0.folder?.id != folder.id }
    }

    private var filtered: [TaskRecord] {
        var result = candidates
        if let status = statusFilter {
            result = result.filter { $0.status == status }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }

    private var statusesPresent: [TaskStatus] {
        let set = Set(candidates.map(\.status))
        return TaskStatus.allCases.filter { set.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if statusesPresent.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(label: "All", isSelected: statusFilter == nil) { statusFilter = nil }
                        ForEach(statusesPresent, id: \.self) { status in
                            FilterChip(
                                label: status.rawValue.capitalized,
                                isSelected: statusFilter == status
                            ) {
                                statusFilter = (statusFilter == status) ? nil : status
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                Divider()
            }
            List {
                if filtered.isEmpty {
                    Text(searchText.isEmpty ? "No tasks available" : "No results for \"\(searchText)\"")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.mutedText)
                } else {
                    ForEach(filtered) { task in
                        let selected = selectedIDs.contains(task.id)
                        Button {
                            if selected { selectedIDs.remove(task.id) }
                            else { selectedIDs.insert(task.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(selected ? Color.accentColor : AppTheme.mutedText)
                                    .animation(AppTheme.Motion.fast, value: selected)
                                Image(systemName: "checklist")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppTheme.subtleText)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(task.status.rawValue.capitalized)
                                        .font(.system(size: 11))
                                        .foregroundStyle(AppTheme.mutedText)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search tasks…")
        .navigationTitle("Add Tasks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !selectedIDs.isEmpty {
                ToolbarItem(placement: .confirmationAction) {
                    AddButton(count: selectedIDs.count) { commitTasks() }
                }
            }
        }
    }

    private func commitTasks() {
        for task in candidates where selectedIDs.contains(task.id) {
            services.captureService.move(task, to: folder, in: modelContext)
        }
        onAdded()
    }
}

// MARK: - Email picker

private struct EmailFolderPicker: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    let folder: FolderRecord
    let onAdded: () -> Void

    @State private var searchText = ""
    @State private var selectedIDs = Set<String>()
    @State private var senderFilter: String? = nil

    private var existingThreadIDs: Set<String> {
        let folderID = folder.id
        let emailType = FolderItemKind.email.rawValue
        let descriptor = FetchDescriptor<FolderItemRecord>(
            predicate: #Predicate { item in
                item.folder?.id == folderID && item.itemType == emailType
            }
        )
        let items = (try? modelContext.fetch(descriptor)) ?? []
        return Set(items.map(\.itemId))
    }

    private var candidates: [EmailThread] {
        services.emailService.threads.filter { !existingThreadIDs.contains($0.id) }
    }

    private var senders: [String] {
        let names = candidates.map { t -> String in
            t.from.name.isEmpty ? t.from.email : t.from.name
        }
        var seen = Set<String>()
        var unique: [String] = []
        for name in names where !seen.contains(name) {
            seen.insert(name)
            unique.append(name)
        }
        return unique.sorted()
    }

    private var filtered: [EmailThread] {
        var result = candidates
        if let sender = senderFilter {
            result = result.filter { t in
                let name = t.from.name.isEmpty ? t.from.email : t.from.name
                return name == sender
            }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.subject.localizedCaseInsensitiveContains(searchText) ||
                $0.from.email.localizedCaseInsensitiveContains(searchText) ||
                $0.from.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            if senders.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(label: "All", isSelected: senderFilter == nil) { senderFilter = nil }
                        ForEach(senders, id: \.self) { sender in
                            FilterChip(label: sender, isSelected: senderFilter == sender) {
                                senderFilter = (senderFilter == sender) ? nil : sender
                            }
                        }
                        // "Select all from sender" shortcut
                        if let sender = senderFilter {
                            Button {
                                let ids = filtered.map(\.id)
                                for id in ids { selectedIDs.insert(id) }
                            } label: {
                                Label("Select all from \(sender)", systemImage: "checkmark.circle")
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(AppTheme.surfaceSecondary))
                                    .foregroundStyle(AppTheme.subtleText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                Divider()
            }
            List {
                if candidates.isEmpty {
                    Text("No emails loaded — open the Inbox tab first")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.mutedText)
                } else if filtered.isEmpty {
                    Text("No results for \"\(searchText)\"")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.mutedText)
                } else {
                    ForEach(filtered) { thread in
                        let selected = selectedIDs.contains(thread.id)
                        Button {
                            if selected { selectedIDs.remove(thread.id) }
                            else { selectedIDs.insert(thread.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(selected ? Color.accentColor : AppTheme.mutedText)
                                    .animation(AppTheme.Motion.fast, value: selected)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(thread.subject)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    HStack(spacing: 4) {
                                        Text(thread.from.name.isEmpty ? thread.from.email : thread.from.name)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(AppTheme.subtleText)
                                        Text("·")
                                            .foregroundStyle(AppTheme.mutedText)
                                        Text(thread.snippet)
                                            .font(.system(size: 12))
                                            .foregroundStyle(AppTheme.mutedText)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 4)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search emails…")
        .navigationTitle("Add Emails")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !selectedIDs.isEmpty {
                ToolbarItem(placement: .confirmationAction) {
                    AddButton(count: selectedIDs.count) { commitEmails() }
                }
            }
        }
    }

    private func commitEmails() {
        for thread in candidates where selectedIDs.contains(thread.id) {
            services.captureService.addItemToFolder(
                kind: .email,
                itemId: thread.id,
                title: thread.subject,
                subtitle: thread.from.name.isEmpty ? thread.from.email : thread.from.name,
                folder: folder,
                in: modelContext
            )
        }
        onAdded()
    }
}

// MARK: - Chat picker

private struct ChatFolderPicker: View {
    @Environment(AppServices.self) private var services

    let folder: FolderRecord
    let onAdded: () -> Void

    @State private var searchText = ""
    @State private var selectedIDs = Set<UUID>()

    private var candidates: [AIChatConversation] {
        services.aiChatService.savedConversations.filter { $0.folderID != folder.id }
    }

    private var filtered: [AIChatConversation] {
        guard !searchText.isEmpty else { return candidates }
        return candidates.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            if candidates.isEmpty {
                Text("No conversations available")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.mutedText)
            } else if filtered.isEmpty {
                Text("No results for \"\(searchText)\"")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.mutedText)
            } else {
                ForEach(filtered) { convo in
                    let selected = selectedIDs.contains(convo.id)
                    Button {
                        if selected { selectedIDs.remove(convo.id) }
                        else { selectedIDs.insert(convo.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(selected ? Color.accentColor : AppTheme.mutedText)
                                .animation(AppTheme.Motion.fast, value: selected)
                            Image(systemName: "bubble.left.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.subtleText)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(convo.title.isEmpty ? "Untitled" : convo.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(convo.createdAt.formatted(.relative(presentation: .named)))
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.mutedText)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search conversations…")
        .navigationTitle("Add Chats")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !selectedIDs.isEmpty {
                ToolbarItem(placement: .confirmationAction) {
                    AddButton(count: selectedIDs.count) { commitChats() }
                }
            }
        }
    }

    private func commitChats() {
        let snapshot = candidates
        for convo in snapshot where selectedIDs.contains(convo.id) {
            services.aiChatService.moveConversation(convo, to: folder.id)
        }
        onAdded()
    }
}

// MARK: - Event picker

private struct EventFolderPicker: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    let folder: FolderRecord
    let onAdded: () -> Void

    @State private var events: [CalendarEvent] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var selectedIDs = Set<String>()

    private var existingEventIDs: Set<String> {
        let folderID = folder.id
        let eventType = FolderItemKind.event.rawValue
        let descriptor = FetchDescriptor<FolderItemRecord>(
            predicate: #Predicate { item in
                item.folder?.id == folderID && item.itemType == eventType
            }
        )
        let items = (try? modelContext.fetch(descriptor)) ?? []
        return Set(items.map(\.itemId))
    }

    private var candidates: [CalendarEvent] {
        events.filter { !existingEventIDs.contains($0.id) }
    }

    private var filtered: [CalendarEvent] {
        guard !searchText.isEmpty else { return candidates }
        return candidates.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            if isLoading {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading upcoming events…")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.mutedText)
                }
            } else if candidates.isEmpty {
                Text("No upcoming events")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.mutedText)
            } else if filtered.isEmpty {
                Text("No results for \"\(searchText)\"")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.mutedText)
            } else {
                ForEach(filtered) { event in
                    let selected = selectedIDs.contains(event.id)
                    Button {
                        if selected { selectedIDs.remove(event.id) }
                        else { selectedIDs.insert(event.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(selected ? Color.accentColor : AppTheme.mutedText)
                                .animation(AppTheme.Motion.fast, value: selected)
                            Image(systemName: "calendar")
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.subtleText)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(event.startDate.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.mutedText)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search events…")
        .navigationTitle("Add Events")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !selectedIDs.isEmpty {
                ToolbarItem(placement: .confirmationAction) {
                    AddButton(count: selectedIDs.count) { commitEvents() }
                }
            }
        }
        .task {
            isLoading = true
            let start = Date()
            let end = Calendar.current.date(byAdding: .day, value: 30, to: start) ?? start
            events = await services.calendarService.events(from: start, to: end)
            isLoading = false
        }
    }

    private func commitEvents() {
        for event in candidates where selectedIDs.contains(event.id) {
            services.captureService.addItemToFolder(
                kind: .event,
                itemId: event.id,
                title: event.title,
                subtitle: event.startDate.formatted(.dateTime.month().day().hour().minute()),
                folder: folder,
                in: modelContext
            )
        }
        onAdded()
    }
}

// MARK: - Doc picker

private struct DocFolderPicker: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    let folder: FolderRecord
    let onAdded: () -> Void

    @State private var searchText = ""
    @State private var selectedIDs = Set<String>()
    @State private var isLoading = false

    private var existingDocIDs: Set<String> {
        let folderID = folder.id
        let docType = FolderItemKind.doc.rawValue
        let descriptor = FetchDescriptor<FolderItemRecord>(
            predicate: #Predicate { item in
                item.folder?.id == folderID && item.itemType == docType
            }
        )
        let items = (try? modelContext.fetch(descriptor)) ?? []
        return Set(items.map(\.itemId))
    }

    private var candidates: [DocRecordDTO] {
        services.docsService.allDocs.filter { !existingDocIDs.contains($0.id) }
    }

    private var filtered: [DocRecordDTO] {
        guard !searchText.isEmpty else { return candidates }
        return candidates.filter {
            ($0.title).localizedCaseInsensitiveContains(searchText) ||
            ($0.contentText ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            if isLoading {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading docs…")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.mutedText)
                }
            } else if candidates.isEmpty {
                Text("No docs available")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.mutedText)
            } else if filtered.isEmpty {
                Text("No results for \"\(searchText)\"")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.mutedText)
            } else {
                ForEach(filtered) { doc in
                    let selected = selectedIDs.contains(doc.id)
                    Button {
                        if selected { selectedIDs.remove(doc.id) }
                        else { selectedIDs.insert(doc.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(selected ? Color.accentColor : AppTheme.mutedText)
                                .animation(AppTheme.Motion.fast, value: selected)
                            Text(doc.emoji ?? "📄")
                                .font(.system(size: 16))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(doc.title.isEmpty ? "Untitled" : doc.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(doc.updatedAt.formatted(.relative(presentation: .named)))
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.mutedText)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search docs…")
        .navigationTitle("Add Docs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !selectedIDs.isEmpty {
                ToolbarItem(placement: .confirmationAction) {
                    AddButton(count: selectedIDs.count) { commitDocs() }
                }
            }
        }
        .task {
            if services.docsService.allDocs.isEmpty {
                isLoading = true
                await services.docsService.refresh()
                isLoading = false
            }
        }
    }

    private func commitDocs() {
        for doc in candidates where selectedIDs.contains(doc.id) {
            services.captureService.addItemToFolder(
                kind: .doc,
                itemId: doc.id,
                title: doc.title.isEmpty ? "Untitled" : doc.title,
                subtitle: doc.updatedAt.formatted(.relative(presentation: .named)),
                folder: folder,
                in: modelContext
            )
        }
        onAdded()
    }
}

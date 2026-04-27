import SwiftUI
import SwiftData

/// Lets the user add an item of any supported type to a folder.
/// Tasks and chats are assigned via their own folderId column. Emails / events
/// are bookmarked through the polymorphic `folder_item` table via TaskCaptureService.
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
                    NavigationLink { taskPicker } label: {
                        rowLabel(icon: "checklist", title: "Task", subtitle: "Move an existing task here")
                    }
                    NavigationLink { emailPicker } label: {
                        rowLabel(icon: "envelope.fill", title: "Email", subtitle: "Pin an email thread")
                    }
                    NavigationLink { chatPicker } label: {
                        rowLabel(icon: "bubble.left.fill", title: "Chat", subtitle: "Save an AI conversation")
                    }
                    NavigationLink { eventPicker } label: {
                        rowLabel(icon: "calendar", title: "Event", subtitle: "Reference a calendar event")
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.mutedText)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(AppTheme.surfaceSecondary)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Doc")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.mutedText)
                            Text("Coming soon")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppTheme.mutedText.opacity(0.7))
                        }
                        Spacer()
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

    // MARK: - Pickers

    @ViewBuilder
    private var taskPicker: some View {
        TaskFolderPicker(folder: folder) {
            onAdded?()
            dismiss()
        }
    }

    @ViewBuilder
    private var emailPicker: some View {
        EmailFolderPicker(folder: folder) {
            onAdded?()
            dismiss()
        }
    }

    @ViewBuilder
    private var chatPicker: some View {
        ChatFolderPicker(folder: folder) {
            onAdded?()
            dismiss()
        }
    }

    @ViewBuilder
    private var eventPicker: some View {
        EventFolderPicker(folder: folder) {
            onAdded?()
            dismiss()
        }
    }
}

// MARK: - Task picker

private struct TaskFolderPicker: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Query(sort: \TaskRecord.updatedAt, order: .reverse) private var tasks: [TaskRecord]

    let folder: FolderRecord
    let onAdded: () -> Void

    private var candidates: [TaskRecord] {
        tasks.filter { $0.folder?.id != folder.id }
    }

    var body: some View {
        List {
            if candidates.isEmpty {
                Text("No tasks available")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.mutedText)
            } else {
                ForEach(candidates) { task in
                    Button {
                        services.captureService.move(task, to: folder, in: modelContext)
                        onAdded()
                    } label: {
                        HStack {
                            Image(systemName: "checklist")
                                .foregroundStyle(AppTheme.subtleText)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text(task.status.rawValue.capitalized)
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.mutedText)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Add Task")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Email picker

private struct EmailFolderPicker: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    let folder: FolderRecord
    let onAdded: () -> Void

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

    var body: some View {
        let threads = services.emailService.threads.filter { !existingThreadIDs.contains($0.id) }
        List {
            if threads.isEmpty {
                Text("No emails loaded — open the Inbox tab first")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.mutedText)
            } else {
                ForEach(threads) { thread in
                    Button {
                        services.captureService.addItemToFolder(
                            kind: .email,
                            itemId: thread.id,
                            title: thread.subject,
                            subtitle: thread.from.name.isEmpty ? thread.from.email : thread.from.name,
                            folder: folder,
                            in: modelContext
                        )
                        onAdded()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(thread.subject)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(thread.snippet)
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.mutedText)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Add Email")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Chat picker

private struct ChatFolderPicker: View {
    @Environment(AppServices.self) private var services

    let folder: FolderRecord
    let onAdded: () -> Void

    var body: some View {
        let conversations = services.aiChatService.savedConversations
            .filter { $0.folderID != folder.id }
        List {
            if conversations.isEmpty {
                Text("No conversations available")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.mutedText)
            } else {
                ForEach(conversations) { convo in
                    Button {
                        services.aiChatService.moveConversation(convo, to: folder.id)
                        onAdded()
                    } label: {
                        HStack {
                            Image(systemName: "bubble.left.fill")
                                .foregroundStyle(AppTheme.subtleText)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(convo.title.isEmpty ? "Untitled" : convo.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(convo.createdAt.formatted(.relative(presentation: .named)))
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.mutedText)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Add Chat")
        .navigationBarTitleDisplayMode(.inline)
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

    var body: some View {
        let filteredEvents = events.filter { !existingEventIDs.contains($0.id) }
        List {
            if isLoading {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading upcoming events…")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.mutedText)
                }
            } else if filteredEvents.isEmpty {
                Text("No upcoming events")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.mutedText)
            } else {
                ForEach(filteredEvents) { event in
                    Button {
                        services.captureService.addItemToFolder(
                            kind: .event,
                            itemId: event.id,
                            title: event.title,
                            subtitle: event.startDate.formatted(.dateTime.month().day().hour().minute()),
                            folder: folder,
                            in: modelContext
                        )
                        onAdded()
                    } label: {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundStyle(AppTheme.subtleText)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text(event.startDate.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.mutedText)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Add Event")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoading = true
            let start = Date()
            let end = Calendar.current.date(byAdding: .day, value: 30, to: start) ?? start
            events = await services.calendarService.events(from: start, to: end)
            isLoading = false
        }
    }
}

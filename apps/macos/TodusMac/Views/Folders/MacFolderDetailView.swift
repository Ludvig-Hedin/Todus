import SwiftUI
import SwiftData

/// macOS folder detail surface — opened via sheet from MacTasksView's folder cards.
/// Mirrors the iOS FolderDetailView with desktop-appropriate density.
struct MacFolderDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(MacAppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let folder: FolderRecord

    @State private var items: [FolderContentItem] = []
    @State private var isLoading = false
    @State private var typeFilter: FolderItemKind? = nil
    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false

    private var accent: Color {
        if let hex = folder.colorHex, let c = Color(hex: hex) { return c }
        return MacTheme.textSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !typesPresent.isEmpty {
                        typeFilters
                    }
                    contents
                }
                .padding(16)
            }
        }
        .frame(minWidth: 540, minHeight: 480)
        .background(MacTheme.contentBackground)
        .task { await load() }
        .sheet(isPresented: $showEditSheet) {
            MacFolderEditSheet(mode: .edit(folder))
        }
        .confirmationDialog(
            "Delete '\(folder.name)'?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    await services.deleteSharedFolder(folder, in: modelContext)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Tasks return to inbox. Saved emails, events, and chats are removed from the folder.")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(0.18))
                    .frame(width: 48, height: 48)
                Image(systemName: folder.iconName ?? "folder.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(MacTheme.textPrimary)
                Text("\(folder.cachedItemCount) item\(folder.cachedItemCount == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
            }
            Spacer()
            Button { showEditSheet = true } label: {
                Image(systemName: "pencil")
            }
            Menu {
                Button("Edit") { showEditSheet = true }
                Button("Delete", role: .destructive) { showDeleteConfirm = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            Button("Done") { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(16)
        .background(
            ZStack {
                MacTheme.surfaceCard
                LinearGradient(
                    colors: [accent.opacity(0.10), accent.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
    }

    private var typesPresent: [FolderItemKind] {
        var seen = Set<FolderItemKind>()
        for item in items where !seen.contains(item.kind) {
            seen.insert(item.kind)
        }
        return FolderItemKind.allCases.filter { seen.contains($0) }
    }

    private var typeFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip(label: "All", count: items.count, isSelected: typeFilter == nil) {
                    typeFilter = nil
                }
                ForEach(typesPresent, id: \.self) { kind in
                    let count = items.filter { $0.kind == kind }.count
                    filterChip(label: label(for: kind), count: count, isSelected: typeFilter == kind) {
                        typeFilter = kind
                    }
                }
            }
        }
    }

    private func filterChip(label: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? accent.opacity(0.9) : MacTheme.mutedText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(isSelected ? accent.opacity(0.18) : MacTheme.surfaceHover))
            .foregroundStyle(isSelected ? accent : MacTheme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var contents: some View {
        let visible = typeFilter == nil ? items : items.filter { $0.kind == typeFilter }
        if isLoading && visible.isEmpty {
            HStack { Spacer(); ProgressView(); Spacer() }
                .padding(.top, 30)
        } else if visible.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "tray")
                    .font(.system(size: 24))
                    .foregroundStyle(MacTheme.mutedText)
                Text("No items yet")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MacTheme.mutedText)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 30)
        } else {
            VStack(spacing: 6) {
                ForEach(visible) { item in
                    MacFolderContentRow(item: item, accent: accent)
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            struct ContentsInput: Encodable {
                let folderId: String
                let limit: Int
            }
            let response: MacFolderContentsResponse = try await services.apiClient.trpcQuery(
                "folders.listContents",
                input: ContentsInput(folderId: folder.id.uuidString, limit: 200)
            )

            let allTasks = (try? modelContext.fetch(FetchDescriptor<TaskRecord>())) ?? []
            let tasksByID = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id.uuidString, $0) })

            var built: [FolderContentItem] = []
            for raw in response.items {
                switch raw.type {
                case "task":
                    if let t = tasksByID[raw.id] { built.append(.task(t)) }
                case "chat":
                    built.append(.chat(id: raw.id, title: raw.title, updatedAt: raw.sortAt))
                case "email":
                    built.append(.email(threadId: raw.id, subject: raw.title, sender: raw.subtitle, date: raw.sortAt))
                case "event":
                    built.append(.event(eventId: raw.id, title: raw.title, start: raw.sortAt))
                case "doc":
                    built.append(.doc(docId: raw.id, title: raw.title, updatedAt: raw.sortAt))
                default:
                    break
                }
            }
            items = built
            await services.fetchFolderSummary(in: modelContext)
        } catch {
            // Best-effort — log so silent failures show up in diagnostics, but keep the UI quiet.
            AppLogger.shared.log("[MacFolderDetailView] load failed: \(error)")
        }
    }

    private func label(for kind: FolderItemKind) -> String {
        switch kind {
        case .task: return "Tasks"
        case .chat: return "Chats"
        case .email: return "Emails"
        case .event: return "Events"
        case .doc: return "Docs"
        }
    }
}

struct MacFolderContentRow: View {
    let item: FolderContentItem
    let accent: Color

    private static let eventDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.opacity(0.14))
                    .frame(width: 28, height: 28)
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                    .lineLimit(2)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(relativeDate(item.sortDate))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(MacTheme.mutedText)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous)
                .fill(MacTheme.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous)
                .strokeBorder(MacTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private var iconName: String {
        switch item.kind {
        case .task: return "checklist"
        case .chat: return "bubble.left.fill"
        case .email: return "envelope.fill"
        case .event: return "calendar"
        case .doc: return "doc.text"
        }
    }

    private var subtitle: String? {
        switch item {
        case .task(let t):
            return t.status.rawValue.capitalized
        case .chat:
            return "Conversation"
        case .email(_, _, let sender, _):
            return sender
        case .event(_, _, let start):
            return Self.eventDateFormatter.string(from: start)
        case .doc:
            return "Document"
        }
    }

    private func relativeDate(_ date: Date) -> String {
        Self.relativeDateFormatter.localizedString(for: date, relativeTo: .now)
    }
}

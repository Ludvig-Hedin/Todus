import SwiftUI
import SwiftData

/// Mixed-type detail view for a single folder. Rendered when the user taps
/// a folder card on Home or the Tasks page.
struct FolderDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let folder: FolderRecord

    @State private var items: [FolderContentItem] = []
    @State private var isLoading = false
    @State private var typeFilter: FolderItemKind? = nil
    @State private var showEditSheet = false
    @State private var showAddSheet = false
    @State private var showDeleteConfirm = false

    private var accent: Color {
        if let hex = folder.colorHex, !hex.isEmpty {
            return Color(hex: hex)
        }
        return AppTheme.subtleText
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                if !typesPresent.isEmpty {
                    typeFilters
                        .padding(.horizontal, 16)
                }

                contents
                    .padding(.horizontal, 16)
                    .padding(.bottom, 80)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.backgroundTop)
        .scrollContentBackground(.hidden)
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showEditSheet = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            addButton
                .padding(.trailing, 20)
                .padding(.bottom, 24)
        }
        .sheet(isPresented: $showEditSheet) {
            FolderEditSheet(mode: .edit(folder))
        }
        .sheet(isPresented: $showAddSheet) {
            AddToFolderSheet(folder: folder, onAdded: { Task { await load() } })
        }
        .confirmationDialog(
            "Delete '\(folder.name)'?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                services.captureService.deleteFolder(folder, in: modelContext)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Tasks in this folder will move back to the inbox. Saved emails, events, and chats will be removed from the folder.")
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accent.opacity(0.18))
                        .frame(width: 56, height: 56)
                    Image(systemName: folder.iconName ?? "folder.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.mutedText)
                }
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                AppTheme.surfacePrimary
                LinearGradient(
                    colors: [accent.opacity(0.15), accent.opacity(0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .strokeBorder(AppTheme.cardBorder, lineWidth: 1)
        )
    }

    // MARK: Type filter row

    private var typesPresent: [FolderItemKind] {
        var seen = Set<FolderItemKind>()
        for item in items where !seen.contains(item.kind) {
            seen.insert(item.kind)
        }
        return FolderItemKind.allCases.filter { seen.contains($0) }
    }

    private var typeFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "All", count: items.count, isSelected: typeFilter == nil) {
                    typeFilter = nil
                }
                ForEach(typesPresent, id: \.self) { kind in
                    let count = items.filter { $0.kind == kind }.count
                    filterChip(
                        label: label(for: kind),
                        count: count,
                        isSelected: typeFilter == kind
                    ) {
                        typeFilter = kind
                    }
                }
            }
        }
    }

    private func filterChip(label: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? accent.opacity(0.9) : AppTheme.mutedText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isSelected ? accent.opacity(0.18) : AppTheme.surfaceSecondary)
            )
            .foregroundStyle(isSelected ? accent : AppTheme.subtleText)
        }
        .buttonStyle(.plain)
    }

    // MARK: Contents

    @ViewBuilder
    private var contents: some View {
        let visible = typeFilter == nil ? items : items.filter { $0.kind == typeFilter }
        if isLoading && visible.isEmpty {
            HStack { Spacer(); ProgressView(); Spacer() }
                .padding(.top, 40)
        } else if visible.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "tray")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(AppTheme.mutedText)
                Text("No items yet")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.mutedText)
                Text("Tap + to add an email, task, chat, or event.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.mutedText.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            VStack(spacing: 8) {
                ForEach(visible) { item in
                    FolderContentRow(item: item, accent: accent)
                }
            }
        }
    }

    // MARK: Add button

    private var addButton: some View {
        Button {
            showAddSheet = true
        } label: {
            ZStack {
                Circle()
                    .fill(accent)
                    .frame(width: 56, height: 56)
                    .shadow(color: accent.opacity(0.35), radius: 14, x: 0, y: 6)
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let fetched = await services.captureService.fetchFolderContents(folder, in: modelContext)
        items = fetched
        // Refresh card cache opportunistically.
        await services.captureService.fetchFolderSummary(in: modelContext)
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

// MARK: - Row

struct FolderContentRow: View {
    let item: FolderContentItem
    let accent: Color

    private static let eventDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(accent.opacity(0.14))
                    .frame(width: 32, height: 32)
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.mutedText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(relativeDate(item.sortDate))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.mutedText)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                .fill(AppTheme.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                .strokeBorder(AppTheme.rowStroke, lineWidth: 1)
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

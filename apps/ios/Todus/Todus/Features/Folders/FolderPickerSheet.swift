import SwiftUI
import SwiftData

/// Reusable sheet that lets the user pick a folder. Used by the "Add to folder…"
/// context menu actions on email threads, calendar events, and AI conversations.
/// Calls the supplied closure with the selected folder; cancelling dismisses without calling the closure.
struct FolderPickerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @Query(
        sort: [
            SortDescriptor(\FolderRecord.position, order: .forward),
            SortDescriptor(\FolderRecord.createdAt, order: .forward),
        ]
    )
    private var folders: [FolderRecord]

    let title: String
    let onPick: (FolderRecord) -> Void

    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            List {
                if folders.isEmpty {
                    Section {
                        Text("You don't have any folders yet.")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.mutedText)
                    }
                } else {
                    Section("Folders") {
                        ForEach(folders) { folder in
                            Button {
                                onPick(folder)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: folder.iconName ?? "folder.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(folder.colorHex.map { Color(hex: $0) } ?? AppTheme.subtleText)
                                        .frame(width: 24)
                                    Text(folder.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(folder.cachedItemCount)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(AppTheme.mutedText)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Button {
                        showCreate = true
                    } label: {
                        Label("New folder", systemImage: "plus.circle")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.sheetBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showCreate) {
                FolderEditSheet(mode: .create) { folder in
                    onPick(folder)
                    dismiss()
                }
                .appSheetBackground()
            }
        }
    }
}

import SwiftUI
import SwiftData

/// Issue #11: Dedicated folder management surface.
/// Users can create, rename, and delete folders in one place rather than
/// having folder creation buried inside task-move sheets.
struct FolderManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Query(sort: \FolderRecord.name) private var folders: [FolderRecord]

    @State private var newFolderName = ""
    @State private var editingFolder: FolderRecord?
    @State private var editName = ""

    var body: some View {
        List {
            // Create new folder
            Section {
                HStack(spacing: 12) {
                    TextField("New folder name", text: $newFolderName)
                        .font(.system(size: 14, weight: .medium))
                        .textFieldStyle(.plain)

                    Button {
                        createFolder()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppTheme.mutedText : Color.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Create")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
            }

            // Existing folders
            Section {
                if folders.isEmpty {
                    Text("No folders yet")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.mutedText)
                } else {
                    ForEach(folders) { folder in
                        folderRow(folder)
                    }
                }
            } header: {
                Text("Folders")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.backgroundTop)
        .navigationTitle("Folders")
        .navigationBarTitleDisplayMode(.inline)
        // Inline rename alert
        .alert("Rename Folder", isPresented: Binding(
            get: { editingFolder != nil },
            set: { if !$0 { editingFolder = nil } }
        )) {
            TextField("New name", text: $editName)
            Button("Rename") {
                renameFolder()
            }
            Button("Cancel", role: .cancel) {
                editingFolder = nil
            }
        } message: {
            Text("Enter a new name for this folder.")
        }
    }

    private func folderRow(_ folder: FolderRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.subtleText)

            Text(folder.name)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteFolder(folder)
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                editingFolder = folder
                editName = folder.name
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(Color.blue)
        }
        .contextMenu {
            Button {
                editingFolder = folder
                editName = folder.name
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive) {
                deleteFolder(folder)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func createFolder() {
        let _ = services.captureService.createFolder(named: newFolderName, in: modelContext)
        newFolderName = ""
    }

    private func renameFolder() {
        guard let folder = editingFolder else { return }
        let cleanedName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return }
        folder.name = cleanedName
        try? modelContext.save()
        editingFolder = nil
    }

    private func deleteFolder(_ folder: FolderRecord) {
        // Unlink tasks from this folder before deleting
        let allTasks = (try? modelContext.fetch(FetchDescriptor<TaskRecord>())) ?? []
        for task in allTasks where task.folder?.id == folder.id {
            task.folder = nil
        }
        modelContext.delete(folder)
        try? modelContext.save()
    }
}

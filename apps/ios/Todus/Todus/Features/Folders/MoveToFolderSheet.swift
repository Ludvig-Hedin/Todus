import SwiftUI
import SwiftData

struct MoveToFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Query(sort: \FolderRecord.name) private var folders: [FolderRecord]

    let task: TaskRecord

    @State private var newFolderName = ""
    @State private var createFolderError: String?

    private var isInInbox: Bool { task.folder == nil }

    var body: some View {
        NavigationStack {
            List {
                Section("Move") {
                    Button {
                        services.captureService.move(task, to: nil, in: modelContext)
                        dismiss()
                    } label: {
                        HStack {
                            Text("Inbox")
                            Spacer()
                            if isInInbox {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppTheme.subtleText)
                            }
                        }
                    }
                    .disabled(isInInbox)
                    .foregroundStyle(isInInbox ? AppTheme.mutedText : Color.primary)

                    ForEach(folders) { folder in
                        let isCurrent = task.folder?.id == folder.id
                        Button {
                            services.captureService.move(task, to: folder, in: modelContext)
                            dismiss()
                        } label: {
                            HStack {
                                Text(folder.name)
                                Spacer()
                                if isCurrent {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AppTheme.subtleText)
                                }
                            }
                        }
                        .disabled(isCurrent)
                        .foregroundStyle(isCurrent ? AppTheme.mutedText : Color.primary)
                    }
                }

                Section {
                    TextField("Folder name", text: $newFolderName)
                    Button("Create and move") {
                        guard let folder = services.captureService.createFolder(named: newFolderName, in: modelContext) else {
                            createFolderError = "Couldn't create that folder. Try a different name."
                            return
                        }
                        createFolderError = nil
                        services.captureService.move(task, to: folder, in: modelContext)
                        dismiss()
                    }
                    .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Create folder")
                } footer: {
                    if let createFolderError {
                        Text(createFolderError)
                            .foregroundStyle(.red)
                    } else if newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Folder name is required")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.sheetBackground)
            .navigationTitle("Move task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}


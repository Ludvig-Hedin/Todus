import SwiftUI
import SwiftData

struct MoveToFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Query(sort: \FolderRecord.name) private var folders: [FolderRecord]

    let task: TaskRecord

    @State private var newFolderName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Move") {
                    Button("Inbox") {
                        services.captureService.move(task, to: nil, in: modelContext)
                        dismiss()
                    }

                    ForEach(folders) { folder in
                        Button(folder.name) {
                            services.captureService.move(task, to: folder, in: modelContext)
                            dismiss()
                        }
                    }
                }

                Section("Create folder") {
                    TextField("Folder name", text: $newFolderName)
                    Button("Create and move") {
                        guard let folder = services.captureService.createFolder(named: newFolderName, in: modelContext) else {
                            return
                        }
                        services.captureService.move(task, to: folder, in: modelContext)
                        dismiss()
                    }
                    .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.backgroundTop)
            .navigationTitle("Move task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}


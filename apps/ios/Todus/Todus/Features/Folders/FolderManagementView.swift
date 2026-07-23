import SwiftUI
import SwiftData

/// Dedicated folder management surface — grid of polished folder cards.
/// Tap a card to edit its name / color / icon. Use the "+" toolbar item or
/// the trailing tile to create a new folder.
struct FolderManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Query(
        sort: [
            SortDescriptor(\FolderRecord.position, order: .forward),
            SortDescriptor(\FolderRecord.createdAt, order: .forward),
        ]
    )
    private var folders: [FolderRecord]

    @State private var editingFolder: FolderRecord?
    @State private var showCreateSheet = false
    @State private var openingFolder: FolderRecord?
    @State private var folderToDelete: FolderRecord?
    @State private var showDeleteError = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(folders) { folder in
                    Button {
                        openingFolder = folder
                    } label: {
                        FolderCardView(folder: folder, layout: .grid)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            openingFolder = folder
                        } label: {
                            Label("Open", systemImage: "arrow.up.right.square")
                        }
                        Button {
                            editingFolder = folder
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            folderToDelete = folder
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                NewFolderCard(layout: .grid) {
                    showCreateSheet = true
                }
            }
            .padding(16)
        }
        .background(AppTheme.backgroundTop)
        .scrollContentBackground(.hidden)
        .navigationTitle("Folders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task {
            await services.captureService.syncSharedFolders(in: modelContext)
            await services.captureService.fetchFolderSummary(in: modelContext)
        }
        .refreshable {
            await services.captureService.syncSharedFolders(in: modelContext)
            await services.captureService.fetchFolderSummary(in: modelContext)
        }
        .sheet(isPresented: $showCreateSheet) {
            FolderEditSheet(mode: .create)
                .appSheetBackground()
        }
        .sheet(item: $editingFolder) { folder in
            FolderEditSheet(mode: .edit(folder))
                .appSheetBackground()
        }
        .sheet(item: $openingFolder) { folder in
            NavigationStack {
                FolderDetailView(folder: folder)
            }
            .presentationDragIndicator(.visible)
            .appSheetBackground()
        }
        .alert(
            "Delete Folder?",
            isPresented: Binding(
                get: { folderToDelete != nil },
                set: { if !$0 { folderToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                folderToDelete = nil
            }
            Button("Delete", role: .destructive) {
                guard let folder = folderToDelete else { return }
                if !services.captureService.deleteFolder(folder, in: modelContext) {
                    showDeleteError = true
                }
                folderToDelete = nil
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Couldn’t Delete Folder", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The folder is still available. Try again.")
        }
    }
}

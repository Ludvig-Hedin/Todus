import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct TaskDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Query(sort: \FolderRecord.name) private var folders: [FolderRecord]

    let task: TaskRecord

    @State private var title: String
    @State private var taskDescription: String
    @State private var status: TaskStatus
    @State private var priority: AppTaskPriority
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    /// Preserves the previously set due date when the toggle is switched off,
    /// so toggling back on restores the user's intended date instead of snapping to .now.
    @State private var savedDueDate: Date?
    @State private var selectedFolderID: UUID?
    @State private var newFolderName = ""
    @State private var isCreatingFolder = false
    @State private var folderCreationErrorMessage = ""
    @State private var showFolderCreationErrorAlert = false
    @State private var attachmentNames: [String]
    @State private var isShowingAttachmentOptions = false
    @State private var isShowingFilePicker = false
    @State private var isShowingPhotoPicker = false
    @State private var isShowingCamera = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    /// Attachment awaiting delete confirmation — nil hides the dialog.
    @State private var pendingDeleteAttachment: String?
    /// Drives the destructive delete-task confirmation dialog.
    @State private var showDeleteTaskConfirmation = false
    /// Guards the Save button from double-fires while the SwiftData write +
    /// subsequent task reschedule are in flight.
    @State private var isSaving = false
    /// Surfaces a persist failure instead of silently closing the sheet — mirrors
    /// the folder-creation error alert already in this view.
    @State private var showSaveErrorAlert = false
    @State private var saveErrorMessage = ""

    init(task: TaskRecord) {
        self.task = task
        _title = State(initialValue: task.title)
        _taskDescription = State(initialValue: task.taskDescription)
        _status = State(initialValue: task.status)
        _priority = State(initialValue: task.priority)
        _hasDueDate = State(initialValue: task.dueDate != nil)
        _dueDate = State(initialValue: task.dueDate ?? .now)
        _selectedFolderID = State(initialValue: task.folderID)
        _attachmentNames = State(initialValue: task.attachmentNames)
    }

    var body: some View {
        NavigationStack {
            List {
                taskSection
                progressSection
                scheduleSection
                organizationSection
                attachmentsSection
                deleteSection
            }
            .listStyle(.insetGrouped)
            .listRowSpacing(10)
            .scrollContentBackground(.hidden)
            .background(AppTheme.sheetBackground)
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        // Attachments imported this session live on disk but were
                        // never persisted to the task — clean them up so Cancel
                        // doesn't leave orphaned files.
                        let added = attachmentNames.filter { !task.attachmentNames.contains($0) }
                        for name in added {
                            AttachmentService.shared.delete(filename: name)
                        }
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        guard !isSaving else { return }
                        isSaving = true
                        saveTask()
                    }
                    .disabled(isSaving || trimmedTitle.isEmpty)
                }
            }
        }
        .confirmationDialog("Add attachment", isPresented: $isShowingAttachmentOptions, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo") {
                    isShowingCamera = true
                }
            }

            Button("Choose from Library") {
                isShowingPhotoPicker = true
            }

            Button("Upload File") {
                isShowingFilePicker = true
            }
        }
        .photosPicker(
            isPresented: $isShowingPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task {
                var savedNames: [String] = []
                for url in urls {
                    if let filename = await AttachmentService.shared.importFile(at: url) {
                        savedNames.append(filename)
                    }
                }
                appendAttachments(savedNames)
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            TaskDetailCameraPicker { image in
                guard let image else { return }
                persistImage(image)
            }
            .ignoresSafeArea()
            .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            // Load actual image data and save to disk
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let filename = await AttachmentService.shared.saveImageDataOffMain(data) {
                    appendAttachments([filename])
                }
            }
            selectedPhotoItem = nil
        }
        .alert("Unable to Create Folder", isPresented: $showFolderCreationErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(folderCreationErrorMessage)
        }
        .alert("Unable to Save Task", isPresented: $showSaveErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
        .confirmationDialog(
            "Remove attachment?",
            isPresented: Binding(
                get: { pendingDeleteAttachment != nil },
                set: { if !$0 { pendingDeleteAttachment = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let name = pendingDeleteAttachment {
                    attachmentNames.removeAll { $0 == name }
                    if task.attachmentNames.contains(name) {
                        // Persisted attachment: only drop the chip here. The file
                        // is deleted in saveTask() after a successful save —
                        // deleting immediately meant Cancel left the persisted
                        // task pointing at a file that no longer existed.
                    } else {
                        // Added this session and never persisted — nothing
                        // references it, so delete the file now (leaving it
                        // orphaned the old way leaked disk space).
                        AttachmentService.shared.delete(filename: name)
                    }
                }
                pendingDeleteAttachment = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteAttachment = nil
            }
        }
        .confirmationDialog(
            "Delete this task?",
            isPresented: $showDeleteTaskConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Task", role: .destructive) {
                services.captureService.delete(task, in: modelContext)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(task.title)\" will be deleted. This can't be undone.")
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteTaskConfirmation = true
            } label: {
                Label("Delete Task", systemImage: "trash")
            }
        }
        .listRowBackground(SheetListRowBackground())
    }

    private var taskSection: some View {
        Section("Task") {
            TextField("Title", text: $title)
            TextField("Description", text: $taskDescription, axis: .vertical)
                .lineLimit(3...8)
        }
        .listRowBackground(SheetListRowBackground())
    }

    private var progressSection: some View {
        Section("Progress") {
            Picker("Status", selection: $status) {
                ForEach(TaskStatus.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.segmented)

            Picker("Priority", selection: $priority) {
                ForEach(AppTaskPriority.allCases) { value in
                    Label(value.title, systemImage: prioritySystemImage(value))
                        .tag(value)
                }
            }
            .pickerStyle(.menu)
        }
        .listRowBackground(SheetListRowBackground())
    }

    private var scheduleSection: some View {
        Section("Schedule") {
            Toggle("Due date", isOn: $hasDueDate)
                .tint(AppTheme.switchTint)
                .onChange(of: hasDueDate) { _, isOn in
                    if !isOn {
                        // Preserve a future date so toggling back on restores it.
                        savedDueDate = dueDate.timeIntervalSinceNow > 0 ? dueDate : nil
                        dueDate = .now
                    } else if let saved = savedDueDate, saved.timeIntervalSinceNow > 0 {
                        dueDate = saved
                        savedDueDate = nil
                    }
                }

            if hasDueDate {
                DatePicker("Due", selection: $dueDate)
            }
        }
        .listRowBackground(SheetListRowBackground())
    }

    private var organizationSection: some View {
        Section {
            Picker("Folder", selection: Binding(
                get: { selectedFolderID?.uuidString ?? "" },
                set: { newValue in
                    selectedFolderID = UUID(uuidString: newValue)
                }
            )) {
                Text("Inbox").tag("")
                ForEach(folders) { folder in
                    Text(folder.name).tag(folder.id.uuidString as String)
                }
            }
            .onChange(of: selectedFolderID) { _, _ in
                isCreatingFolder = false
                newFolderName = ""
            }

            if isCreatingFolder {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("New folder name", text: $newFolderName)
                        .autocorrectionDisabled()

                    if !folderCreationErrorMessage.isEmpty {
                        Text(folderCreationErrorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }

                    HStack {
                        Button("Cancel") {
                            isCreatingFolder = false
                            newFolderName = ""
                            folderCreationErrorMessage = ""
                        }
                        .foregroundStyle(AppTheme.mutedText)

                        Spacer()

                        Button("Create Folder") {
                            createFolder()
                        }
                        .disabled(trimmedNewFolderName.isEmpty)
                    }
                    .font(.system(size: 14, weight: .semibold))
                }
            } else {
                Button {
                    isCreatingFolder = true
                    folderCreationErrorMessage = ""
                } label: {
                    Label("Create new folder", systemImage: "folder.badge.plus")
                }
            }
        } header: {
            Text("Organization")
        } footer: {
            if isCreatingFolder {
                Text("Create the folder here and the task will move into it immediately.")
                    .font(.system(size: 12))
            } else if selectedFolderID == nil {
                Text("This task is currently in Inbox.")
                    .font(.system(size: 12))
            }
        }
        .listRowBackground(SheetListRowBackground())
    }

    private var attachmentsSection: some View {
        Section("Attachments") {
            Button {
                isShowingAttachmentOptions = true
            } label: {
                Label(
                    attachmentNames.isEmpty ? "Add attachment" : "Add another attachment",
                    systemImage: "paperclip.badge.plus"
                )
            }

            if attachmentNames.isEmpty {
                Text("Photos and files you attach here stay with the task.")
                    .foregroundStyle(AppTheme.mutedText)
            } else {
                ForEach(attachmentNames, id: \.self) { name in
                    HStack(spacing: 12) {
                        if AttachmentService.shared.isImageFile(name) {
                            AttachmentThumbnailView(filename: name, size: 40) {
                                RoundedRectangle(cornerRadius: AppTheme.Radius.inline, style: .continuous)
                                    .fill(AppTheme.surfaceSecondary)
                            }
                        } else {
                            Image(systemName: "paperclip")
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.mutedText)
                                .frame(width: 40, height: 40)
                                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.inline, style: .continuous))
                        }

                        Text(name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(name)
                            .accessibilityLabel("Attachment: \(name)")

                        Spacer()

                        Button(role: .destructive) {
                            pendingDeleteAttachment = name
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .minTouchTarget()
                    }
                }
            }
        }
        .listRowBackground(SheetListRowBackground())
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNewFolderName: String {
        newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func prioritySystemImage(_ value: AppTaskPriority) -> String {
        switch value {
        case .none:
            return "minus.circle"
        case .low:
            return "flag"
        case .medium:
            return "flag.fill"
        case .high:
            return "exclamationmark.circle.fill"
        }
    }

    private func createFolder() {
        guard !trimmedNewFolderName.isEmpty else { return }
        guard let folder = services.captureService.createFolder(named: trimmedNewFolderName, in: modelContext) else {
            folderCreationErrorMessage = "Could not create the folder. Please try a different name."
            showFolderCreationErrorAlert = true
            AppLogger.shared.log("TaskDetailSheet: failed to create folder named \(trimmedNewFolderName)")
            return
        }
        selectedFolderID = folder.id
        newFolderName = ""
        folderCreationErrorMessage = ""
        isCreatingFolder = false
    }

    private func appendAttachments(_ names: [String]) {
        attachmentNames.append(contentsOf: names)
    }

    private func persistImage(_ image: UIImage) {
        Task { @MainActor in
            if let filename = await AttachmentService.shared.saveImageOffMain(image) {
                appendAttachments([filename])
            }
        }
    }

    private func saveTask() {
        // Snapshot before updateTaskDetails mutates task.attachmentNames, so we
        // can delete removed files from disk only after the save succeeds.
        let originalAttachments = task.attachmentNames
        let folder = folders.first(where: { $0.id == selectedFolderID })
        services.captureService.updateTaskDetails(
            task,
            title: trimmedTitle,
            taskDescription: taskDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            status: status,
            priority: priority,
            dueDate: hasDueDate ? dueDate : nil,
            folder: folder,
            attachmentNames: attachmentNames,
            in: modelContext
        )
        // `updateTaskDetails` persists internally but swallows save errors. Re-save here
        // so a disk-full / corrupt-store failure surfaces to the user instead of the sheet
        // silently closing with unsaved edits. If the internal save already succeeded this
        // is a harmless no-op (nothing left pending to flush).
        do {
            try modelContext.save()
            // Save landed — now it's safe to delete files the user removed.
            for name in originalAttachments where !attachmentNames.contains(name) {
                AttachmentService.shared.delete(filename: name)
            }
            isSaving = false
            dismiss()
        } catch {
            AppLogger.shared.log("TaskDetailSheet.saveTask: save failed: \(error.localizedDescription)")
            isSaving = false
            saveErrorMessage = "Your changes couldn't be saved. Please try again."
            showSaveErrorAlert = true
        }
    }
}

private struct TaskDetailCameraPicker: UIViewControllerRepresentable {
    let onComplete: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onComplete: (UIImage?) -> Void

        init(onComplete: @escaping (UIImage?) -> Void) {
            self.onComplete = onComplete
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            onComplete(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            picker.dismiss(animated: true)
            // Extract the actual captured image
            let image = info[.originalImage] as? UIImage
            onComplete(image)
        }
    }
}

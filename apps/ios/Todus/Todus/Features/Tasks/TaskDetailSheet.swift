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
    @State private var selectedFolderID: UUID?
    @State private var newFolderName = ""
    @State private var attachmentNames: [String]
    @State private var isShowingAttachmentOptions = false
    @State private var isShowingFilePicker = false
    @State private var isShowingPhotoPicker = false
    @State private var isShowingCamera = false
    @State private var selectedPhotoItem: PhotosPickerItem?

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
                basicsSection
                scheduleSection
                organizationSection
                attachmentsSection
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.backgroundTop)
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveTask()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            var savedNames: [String] = []
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url) {
                    let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension
                    if let filename = AttachmentService.shared.saveData(data, fileExtension: ext) {
                        savedNames.append(filename)
                    }
                }
            }
            appendAttachments(savedNames)
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            TaskDetailCameraPicker { image in
                // Save the actual captured image to disk
                if let image = image,
                   let filename = AttachmentService.shared.saveImage(image) {
                    appendAttachments([filename])
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            // Load actual image data and save to disk
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data),
                   let filename = AttachmentService.shared.saveImage(uiImage) {
                    appendAttachments([filename])
                }
            }
            selectedPhotoItem = nil
        }
    }

    private var basicsSection: some View {
        Section("Basics") {
            TextField("Title", text: $title)

            TextField("Description", text: $taskDescription, axis: .vertical)
                .lineLimit(3...8)

            Picker("Status", selection: $status) {
                ForEach(TaskStatus.allCases) { value in
                    Text(value.title).tag(value)
                }
            }

            Picker("Priority", selection: $priority) {
                ForEach(AppTaskPriority.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
        }
    }

    private var scheduleSection: some View {
        Section("Deadline") {
            Toggle("Has deadline", isOn: $hasDueDate)
                .tint(Color.blue)

            if hasDueDate {
                DatePicker("Due", selection: $dueDate)
            }
        }
    }

    private var organizationSection: some View {
        Section("Folder") {
            Picker("Folder", selection: Binding(
                get: { selectedFolderID?.uuidString ?? "" },
                set: { newValue in
                    selectedFolderID = UUID(uuidString: newValue)
                }
            )) {
                Text("Inbox").tag("")
                ForEach(folders) { folder in
                    Text(folder.name).tag(folder.id.uuidString)
                }
            }

            TextField("New folder", text: $newFolderName)

            Button("Create folder") {
                guard let folder = services.captureService.createFolder(named: newFolderName, in: modelContext) else {
                    return
                }
                selectedFolderID = folder.id
                newFolderName = ""
            }
            .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var attachmentsSection: some View {
        Section("Attachments") {
            if attachmentNames.isEmpty {
                Text("No attachments yet")
                    .foregroundStyle(AppTheme.mutedText)
            } else {
                ForEach(attachmentNames, id: \.self) { name in
                    HStack(spacing: 12) {
                        // Show thumbnail if it's an image, otherwise show generic icon
                        if let image = AttachmentService.shared.loadImage(for: name) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            Image(systemName: "paperclip")
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.mutedText)
                                .frame(width: 40, height: 40)
                                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }

                        Text(name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button(role: .destructive) {
                            attachmentNames.removeAll { $0 == name }
                            AttachmentService.shared.delete(filename: name)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button("Add attachment") {
                isShowingAttachmentOptions = true
            }
        }
    }

    private func appendAttachments(_ names: [String]) {
        attachmentNames.append(contentsOf: names)
    }

    private func saveTask() {
        let folder = folders.first(where: { $0.id == selectedFolderID })
        services.captureService.updateTaskDetails(
            task,
            title: title,
            taskDescription: taskDescription,
            status: status,
            priority: priority,
            dueDate: hasDueDate ? dueDate : nil,
            folder: folder,
            attachmentNames: attachmentNames,
            in: modelContext
        )
        dismiss()
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

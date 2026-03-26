import PhotosUI
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

/// Bottom composer bar for quick task capture.
/// Redesigned with send button in a bottom toolbar row alongside folder and deadline selectors.
/// Supports slash-menu shortcuts, markdown bullet auto-format, and image paste.
struct CaptureComposer: View {
    @Binding var text: String
    /// Submit closure now receives pending attachment filenames, selected folder, and optional due date override.
    let onSubmit: (_ attachmentNames: [String], _ folder: FolderRecord?, _ dueDate: Date?) -> Void

    @State private var isPickingAttachment = false   // triggers native confirmationDialog
    @State private var isShowingFilePicker = false
    @State private var isShowingPhotoPicker = false
    @State private var isShowingCamera = false
    @State private var isShowingDeadlinePicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    /// Pending attachment filenames collected before submit
    @State private var pendingAttachments: [String] = []

    /// Composer metadata — persisted between sends for batch-capture to same folder/date
    @State private var selectedFolder: FolderRecord? = nil
    @State private var selectedDueDate: Date? = nil

    /// Slash-command quick actions menu
    @State private var showsSlashMenu = false

    @Query(sort: \FolderRecord.createdAt) private var folders: [FolderRecord]

    private let controlSize: CGFloat = 44

    var body: some View {
        VStack(spacing: 8) {
            // Slash menu floats above the composer when "/" is the last character typed
            if showsSlashMenu {
                slashMenuPanel
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // ZStack positions the custom attachment panel above the + button
            ZStack(alignment: .bottomLeading) {
                inputRow

                // Attachment picker panel — floats above + button, anchored bottom-leading
                if isPickingAttachment {
                    composerAttachmentPanel
                        .padding(.bottom, controlSize + 8)
                        .transition(.scale(scale: 0.85, anchor: .bottomLeading).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, 2)
        .animation(.snappy(duration: 0.18), value: showsSlashMenu)
        .animation(.snappy(duration: 0.15), value: selectedFolder?.id)
        .animation(.snappy(duration: 0.15), value: selectedDueDate)
        .animation(.snappy(duration: 0.15), value: isPickingAttachment)
        // Deadline picker sheet with native graphical DatePicker
        .sheet(isPresented: $isShowingDeadlinePicker) {
            deadlinePickerSheet
                .presentationDetents([.height(420)])
                .presentationDragIndicator(.visible)
                .presentationBackground(AppTheme.backgroundTop)
        }
        .photosPicker(isPresented: $isShowingPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url) {
                    let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension
                    if let filename = AttachmentService.shared.saveData(data, fileExtension: ext) {
                        pendingAttachments.append(filename)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { image in
                if let image = image,
                   let filename = AttachmentService.shared.saveImage(image) {
                    pendingAttachments.append(filename)
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data),
                   let filename = AttachmentService.shared.saveImage(uiImage) {
                    pendingAttachments.append(filename)
                }
            }
            selectedPhotoItem = nil
        }
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // Attachment trigger — toggles custom panel anchored above this button
            Button {
                withAnimation(.snappy(duration: 0.15)) { isPickingAttachment.toggle() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(width: controlSize, height: controlSize)
            }
            .buttonStyle(.plain)
            .background(AppTheme.surfacePrimary, in: Circle())
            .overlay(Circle().stroke(AppTheme.strongBorder, lineWidth: 1))

            // Main input box: attachments (if any) + text on top, toolbar on bottom
            VStack(spacing: 0) {
                // Attachment thumbnails inside the box, above the text field
                if !pendingAttachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(pendingAttachments, id: \.self) { filename in
                                composerAttachmentThumbnail(filename: filename)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 2)
                }

                // Text input — UITextView wrapper intercepts image paste
                PasteHandlingTextInput(
                    text: $text,
                    placeholder: "Dump a task, thought, or a pasted list",
                    onPasteImage: handlePastedImage
                )
                // No fixed height — UITextView grows with content automatically
                .padding(.top, pendingAttachments.isEmpty ? 12 : 6)
                .padding(.horizontal, 16)
                .onChange(of: text) { _, value in
                    handleTextChange(value)
                }

                // Toolbar row: folder | deadline | send
                HStack(spacing: 4) {
                    // Folder selector — shows current folders from SwiftData
                    Menu {
                        Button {
                            selectedFolder = nil
                        } label: {
                            Label("Auto (AI decides)", systemImage: "sparkles")
                        }
                        if !folders.isEmpty {
                            Divider()
                            ForEach(folders) { folder in
                                Button {
                                    selectedFolder = folder
                                } label: {
                                    Label(folder.name, systemImage: "folder")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: selectedFolder == nil ? "tray" : "folder.fill")
                                .font(.system(size: 13, weight: .semibold))
                            if let folder = selectedFolder {
                                Text(folder.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                            }
                        }
                        .foregroundStyle(selectedFolder == nil ? AppTheme.mutedText : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            selectedFolder != nil ? AppTheme.surfaceSecondary : Color.clear,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)

                    // Deadline selector — opens DatePicker sheet
                    Button {
                        // Default to 1 hour from now when opening for the first time
                        if selectedDueDate == nil {
                            selectedDueDate = Date().addingTimeInterval(3600)
                        }
                        isShowingDeadlinePicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: selectedDueDate == nil ? "clock" : "clock.fill")
                                .font(.system(size: 13, weight: .semibold))
                            if let due = selectedDueDate {
                                Text(due, format: .dateTime.month(.abbreviated).day().hour().minute())
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                            }
                        }
                        .foregroundStyle(selectedDueDate == nil ? AppTheme.mutedText : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            selectedDueDate != nil ? AppTheme.surfaceSecondary : Color.clear,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Voice transcription — muted mic idle, red stop when recording, spinner when transcribing
                    VoiceInputButton { transcribed in
                        let current = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        text = current.isEmpty ? transcribed : current + " " + transcribed
                    }

                    // Send button — visually disabled (0.4 opacity) when input is empty
                    let sendDisabled = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingAttachments.isEmpty
                    Button(action: submitTask) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .clipShape(Circle())
                    .disabled(sendDisabled)
                    .opacity(sendDisabled ? 0.4 : 1)
                    .animation(.easeOut(duration: 0.12), value: sendDisabled)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .background(
                AppTheme.surfacePrimary,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AppTheme.strongBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Slash Menu Panel

    private var slashMenuPanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            slashAction(title: "Due Today", icon: "sun.max", color: .orange) {
                applySlashAction { setDueDateToToday() }
            }
            slashAction(title: "Due Tomorrow", icon: "sunrise", color: .blue) {
                applySlashAction { setDueDateToTomorrow() }
            }
            slashAction(title: "Due Next Week", icon: "calendar.badge.plus", color: .purple) {
                applySlashAction { setDueDateToNextWeek() }
            }
            slashAction(title: "In 1 Hour", icon: "clock", color: .green) {
                applySlashAction { selectedDueDate = Date().addingTimeInterval(3600) }
            }
        }
        .padding(8)
        .background(
            AppTheme.surfacePrimary,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.strongBorder, lineWidth: 1)
        )
        .shadow(color: AppTheme.shadowColor, radius: 12, x: 0, y: -4)
    }

    private func slashAction(
        title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func applySlashAction(_ configure: () -> Void) {
        // Remove the "/" trigger from the text before applying the action
        if text.hasSuffix("/") {
            text = String(text.dropLast())
        }
        configure()
        withAnimation(.snappy(duration: 0.18)) {
            showsSlashMenu = false
        }
    }

    // MARK: - Deadline Picker Sheet

    private var deadlinePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker(
                    "Due Date",
                    selection: Binding(
                        get: { selectedDueDate ?? Date().addingTimeInterval(3600) },
                        set: { selectedDueDate = $0 }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .padding(.horizontal, 16)

                if selectedDueDate != nil {
                    Button(role: .destructive) {
                        selectedDueDate = nil
                        isShowingDeadlinePicker = false
                    } label: {
                        Label("Clear Due Date", systemImage: "xmark.circle")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(AppTheme.danger)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Set Deadline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isShowingDeadlinePicker = false }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Text Change Handling

    private func handleTextChange(_ value: String) {
        // Show slash menu when the last non-whitespace character is "/"
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        withAnimation(.snappy(duration: 0.15)) {
            showsSlashMenu = trimmed.hasSuffix("/") && !trimmed.isEmpty
        }
    }

    // MARK: - Due Date Helpers

    private func setDueDateToToday() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        selectedDueDate = cal.date(byAdding: .hour, value: 23, to: today) ?? today
    }

    private func setDueDateToTomorrow() {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        selectedDueDate = cal.date(byAdding: .hour, value: 9, to: tomorrow) ?? tomorrow
    }

    private func setDueDateToNextWeek() {
        let cal = Calendar.current
        let nextWeek = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: Date()))!
        selectedDueDate = cal.date(byAdding: .hour, value: 9, to: nextWeek) ?? nextWeek
    }

    // MARK: - Image Paste Handler

    private func handlePastedImage(_ image: UIImage) {
        if let filename = AttachmentService.shared.saveImage(image) {
            pendingAttachments.append(filename)
        }
    }

    // MARK: - Submit

    private func submitTask() {
        let attachments = pendingAttachments
        let folder = selectedFolder
        let dueDate = selectedDueDate
        pendingAttachments = []
        // Don't reset folder/dueDate — lets the user batch-capture to same context
        onSubmit(attachments, folder, dueDate)
    }

    // MARK: - Attachment Thumbnail & Picker Panel

    /// Single attachment thumbnail — X button contained within image bounds.
    @ViewBuilder
    private func composerAttachmentThumbnail(filename: String) -> some View {
        ZStack(alignment: .topTrailing) {
            if let image = AttachmentService.shared.loadImage(for: filename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.surfaceSecondary)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "doc")
                            .font(.system(size: 18))
                            .foregroundStyle(AppTheme.mutedText)
                    )
            }
            // X button inset within image bounds — .padding(4) keeps it inside, no offset clipping
            Button {
                pendingAttachments.removeAll { $0 == filename }
                AttachmentService.shared.delete(filename: filename)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .background(Color.black.opacity(0.5), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(4)
        }
    }

    /// Custom attachment picker panel — floats above + button anchored bottom-leading.
    /// Replaces native confirmationDialog for better spatial positioning near the trigger.
    private var composerAttachmentPanel: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.15)) { isPickingAttachment = false }
                isShowingPhotoPicker = true
            } label: { composerMenuRow(icon: "photo.on.rectangle", label: "Photo Library") }
            .buttonStyle(.plain)

            Divider().opacity(0.4)

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    withAnimation(.snappy(duration: 0.15)) { isPickingAttachment = false }
                    isShowingCamera = true
                } label: { composerMenuRow(icon: "camera", label: "Take Photo") }
                .buttonStyle(.plain)

                Divider().opacity(0.4)
            }

            Button {
                withAnimation(.snappy(duration: 0.15)) { isPickingAttachment = false }
                isShowingFilePicker = true
            } label: { composerMenuRow(icon: "doc.badge.plus", label: "Choose File") }
            .buttonStyle(.plain)
        }
        .frame(width: 210)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 4)
    }

    private func composerMenuRow(icon: String, label: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 22)
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - PasteHandlingTextInput

/// UITextView wrapper that intercepts paste to detect images from the clipboard
/// and provides auto-formatting for markdown bullet lists.
struct PasteHandlingTextInput: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onPasteImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, placeholder: placeholder, onPasteImage: onPasteImage)
    }

    func makeUIView(context: Context) -> PasteInterceptingTextView {
        let view = PasteInterceptingTextView()
        view.delegate = context.coordinator
        view.onPasteImage = onPasteImage
        view.backgroundColor = .clear
        view.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        // Disabled so SwiftUI's layout drives the height based on content
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // Hug content vertically so the view shrinks to one line when empty
        view.setContentHuggingPriority(.defaultHigh, for: .vertical)

        // Show placeholder initially
        if text.isEmpty {
            view.text = placeholder
            view.textColor = UIColor.placeholderText
        } else {
            view.text = text
            view.textColor = UIColor.label
        }

        // Auto-focus after the view appears — matches original 250ms delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            view.becomeFirstResponder()
        }
        return view
    }

    func updateUIView(_ uiView: PasteInterceptingTextView, context: Context) {
        // Only sync when text is changed externally (e.g. after submit clears it)
        guard text != context.coordinator.lastKnownText else { return }
        context.coordinator.lastKnownText = text

        if text.isEmpty {
            if uiView.isFirstResponder {
                // Clear content but keep keyboard open
                uiView.text = ""
                uiView.textColor = UIColor.label
            } else {
                uiView.text = placeholder
                uiView.textColor = UIColor.placeholderText
            }
        } else {
            uiView.text = text
            uiView.textColor = UIColor.label
        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        let placeholder: String
        let onPasteImage: (UIImage) -> Void
        /// Tracks the last text value the coordinator wrote to the binding,
        /// used to distinguish external (submit) clears from internal edits.
        var lastKnownText: String = ""

        init(
            text: Binding<String>,
            placeholder: String,
            onPasteImage: @escaping (UIImage) -> Void
        ) {
            _text = text
            self.placeholder = placeholder
            self.onPasteImage = onPasteImage
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            // Replace placeholder with empty field on focus
            if textView.textColor == UIColor.placeholderText {
                textView.text = ""
                textView.textColor = UIColor.label
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textView.text = placeholder
                textView.textColor = UIColor.placeholderText
                text = ""
                lastKnownText = ""
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            guard textView.textColor != UIColor.placeholderText else { return }
            var updatedText = textView.text ?? ""

            // Auto-format: replace "- " at start of a line with "• " (markdown bullets)
            let lines = updatedText.components(separatedBy: "\n")
            var modified = false
            let newLines = lines.map { line -> String in
                if line.hasPrefix("- ") {
                    modified = true
                    return "• " + line.dropFirst(2)
                }
                return line
            }
            if modified {
                updatedText = newLines.joined(separator: "\n")
                textView.text = updatedText
            }

            lastKnownText = updatedText
            text = updatedText
            // Notify SwiftUI layout to re-measure height from intrinsicContentSize
            textView.invalidateIntrinsicContentSize()
        }
    }
}

// MARK: - PasteInterceptingTextView

/// UITextView subclass that intercepts paste to detect images from the clipboard.
/// Overrides intrinsicContentSize so SwiftUI's layout system drives height from content,
/// not from available space — keeping the composer at single-line until the user types.
final class PasteInterceptingTextView: UITextView {
    var onPasteImage: ((UIImage) -> Void)?

    override var intrinsicContentSize: CGSize {
        // Measure the height required for the current content
        let measured = sizeThatFits(
            CGSize(width: frame.width > 0 ? frame.width : UIScreen.main.bounds.width,
                   height: .greatestFiniteMagnitude)
        )
        return CGSize(width: UIView.noIntrinsicMetric, height: max(measured.height, 20))
    }

    override func paste(_ sender: Any?) {
        // Check for image in pasteboard before falling through to default text paste
        if let image = UIPasteboard.general.image {
            onPasteImage?(image)
        } else {
            super.paste(sender)
        }
    }
}

// MARK: - CameraPicker

/// Camera picker that returns the actual captured UIImage.
/// Internal so it can also be used by AIChatView.
struct CameraPicker: UIViewControllerRepresentable {
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
            let image = info[.originalImage] as? UIImage
            onComplete(image)
        }
    }
}


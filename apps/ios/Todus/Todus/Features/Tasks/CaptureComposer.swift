import PhotosUI
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

enum RichInputSurface {
    case emailCompose
    case aiChat
    case taskCapture
}

enum RichInputMentionKind: String, Codable, Hashable {
    case task
    case thread
    case event
    case person
}

struct RichInputMentionRef: Identifiable, Codable, Hashable {
    let id: String
    let kind: RichInputMentionKind
    let title: String
    let subtitle: String?
    let displayText: String
    let accessibilityLabel: String
}

enum RichInputCommandAction: Hashable {
    case paragraph
    case heading1
    case heading2
    case heading3
    case bulletList
    case numberedList
    case checklist
    case divider
    case quote
    case insertMention(RichInputMentionKind)
    case signature
    case dueToday
    case dueTomorrow
    case dueNextWeek
    case inOneHour
}

struct RichInputCommand: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let action: RichInputCommandAction
}

private func richInputCommands(for surface: RichInputSurface) -> [RichInputCommand] {
    switch surface {
    case .emailCompose:
        return [
            .init(id: "paragraph", title: "Paragraph", subtitle: "Continue with plain text", systemImage: "text.alignleft", action: .paragraph),
            .init(id: "heading1", title: "Heading 1", subtitle: "Insert a large heading", systemImage: "textformat.size.larger", action: .heading1),
            .init(id: "heading2", title: "Heading 2", subtitle: "Insert a medium heading", systemImage: "textformat.size", action: .heading2),
            .init(id: "heading3", title: "Heading 3", subtitle: "Insert a small heading", systemImage: "textformat.size.smaller", action: .heading3),
            .init(id: "bullet", title: "Bullet List", subtitle: "Insert a bulleted list", systemImage: "list.bullet", action: .bulletList),
            .init(id: "numbered", title: "Numbered List", subtitle: "Insert a numbered list", systemImage: "list.number", action: .numberedList),
            .init(id: "checklist", title: "Checklist", subtitle: "Insert a checklist", systemImage: "checklist", action: .checklist),
            .init(id: "divider", title: "Divider", subtitle: "Insert a divider", systemImage: "minus", action: .divider),
            .init(id: "quote", title: "Quote", subtitle: "Insert a quote block", systemImage: "quote.opening", action: .quote),
            .init(id: "task", title: "Task Mention", subtitle: "Search and insert a task", systemImage: "checklist", action: .insertMention(.task)),
            .init(id: "thread", title: "Email Thread", subtitle: "Search and insert an email thread", systemImage: "envelope", action: .insertMention(.thread)),
            .init(id: "event", title: "Event", subtitle: "Search and insert an event", systemImage: "calendar", action: .insertMention(.event)),
            .init(id: "person", title: "Person", subtitle: "Search and insert a person", systemImage: "person.2", action: .insertMention(.person)),
            .init(id: "signature", title: "Signature", subtitle: "Insert your active signature", systemImage: "signature", action: .signature),
        ]
    case .aiChat:
        return [
            .init(id: "task", title: "Task Mention", subtitle: "Search and insert a task", systemImage: "checklist", action: .insertMention(.task)),
            .init(id: "thread", title: "Email Thread", subtitle: "Search and insert an email thread", systemImage: "envelope", action: .insertMention(.thread)),
            .init(id: "event", title: "Event", subtitle: "Search and insert an event", systemImage: "calendar", action: .insertMention(.event)),
            .init(id: "person", title: "Person", subtitle: "Search and insert a person", systemImage: "person.2", action: .insertMention(.person)),
            .init(id: "paragraph", title: "Paragraph", subtitle: "Continue with plain text", systemImage: "text.alignleft", action: .paragraph),
            .init(id: "bullet", title: "Bullet List", subtitle: "Insert a bulleted list", systemImage: "list.bullet", action: .bulletList),
            .init(id: "numbered", title: "Numbered List", subtitle: "Insert a numbered list", systemImage: "list.number", action: .numberedList),
            .init(id: "checklist", title: "Checklist", subtitle: "Insert a checklist", systemImage: "checklist", action: .checklist),
            .init(id: "divider", title: "Divider", subtitle: "Insert a divider", systemImage: "minus", action: .divider),
            .init(id: "quote", title: "Quote", subtitle: "Insert a quote block", systemImage: "quote.opening", action: .quote),
        ]
    case .taskCapture:
        return [
            .init(id: "due-today", title: "Due Today", subtitle: "Set the due date to today", systemImage: "sun.max", action: .dueToday),
            .init(id: "due-tomorrow", title: "Due Tomorrow", subtitle: "Set the due date to tomorrow", systemImage: "sunrise", action: .dueTomorrow),
            .init(id: "due-next-week", title: "Due Next Week", subtitle: "Set the due date to next week", systemImage: "calendar.badge.plus", action: .dueNextWeek),
            .init(id: "in-one-hour", title: "In 1 Hour", subtitle: "Set the due date to one hour from now", systemImage: "clock", action: .inOneHour),
        ]
    }
}

private func applyRichInputFormatting(_ action: RichInputCommandAction) -> String {
    switch action {
    case .paragraph:
        return ""
    case .heading1:
        return "# "
    case .heading2:
        return "## "
    case .heading3:
        return "### "
    case .bulletList:
        return "• "
    case .numberedList:
        return "1. "
    case .checklist:
        return "☐ "
    case .divider:
        return "\n---\n"
    case .quote:
        return "> "
    case .insertMention:
        return "@"
    case .signature, .dueToday, .dueTomorrow, .dueNextWeek, .inOneHour:
        return ""
    }
}

/// Bottom composer bar for quick task capture.
/// Redesigned with send button in a bottom toolbar row alongside folder and deadline selectors.
/// Supports slash-menu shortcuts, markdown bullet auto-format, and image paste.
struct CaptureComposer: View {
    @Environment(AppServices.self) private var services
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
                .preferredColorScheme(services.appearancePreference.colorScheme)
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
                    .minTouchTarget()
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
            ForEach(richInputCommands(for: .taskCapture)) { command in
                slashAction(title: command.title, icon: command.systemImage, color: slashActionColor(for: command.action)) {
                    applySlashAction(command.action)
                }
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

    private func applySlashAction(_ action: RichInputCommandAction) {
        // Remove the "/" trigger from the text before applying the action
        if text.hasSuffix("/") {
            text = String(text.dropLast())
        }
        switch action {
        case .dueToday:
            setDueDateToToday()
        case .dueTomorrow:
            setDueDateToTomorrow()
        case .dueNextWeek:
            setDueDateToNextWeek()
        case .inOneHour:
            selectedDueDate = Date().addingTimeInterval(3600)
        default:
            break
        }
        withAnimation(.snappy(duration: 0.18)) {
            showsSlashMenu = false
        }
    }

    private func slashActionColor(for action: RichInputCommandAction) -> Color {
        switch action {
        case .dueToday:
            return .orange
        case .dueTomorrow:
            return .blue
        case .dueNextWeek:
            return .purple
        case .inOneHour:
            return .green
        default:
            return AppTheme.mutedText
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

struct RichComposerInput: View {
    @Binding var text: String
    @Binding var mentions: [RichInputMentionRef]

    let placeholder: String
    let surface: RichInputSurface
    let mentionOptions: [RichInputMentionRef]
    var isFocused: Bool? = nil
    var onPasteImage: ((UIImage) -> Void)? = nil
    var onCommand: ((RichInputCommandAction) -> Void)? = nil

    @State private var activeMentionQuery = ""
    @State private var activeSlashQuery = ""
    @State private var showsMentionMenu = false
    @State private var showsSlashMenu = false
    @State private var preferredMentionKind: RichInputMentionKind? = nil
    @State private var suppressSuggestionReopen = false

    private var filteredMentions: [RichInputMentionRef] {
        let normalized = activeMentionQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return mentionOptions.filter { mention in
            if let preferredMentionKind, mention.kind != preferredMentionKind {
                return false
            }

            if normalized.isEmpty {
                return true
            }

            return mention.title.lowercased().contains(normalized)
                || mention.displayText.lowercased().contains(normalized)
                || (mention.subtitle?.lowercased().contains(normalized) ?? false)
        }
    }

    private var filteredSlashCommands: [RichInputCommand] {
        let normalized = activeSlashQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let commands = richInputCommands(for: surface)

        guard !normalized.isEmpty else { return commands }

        return commands.filter {
            $0.title.lowercased().contains(normalized) || $0.subtitle.lowercased().contains(normalized)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsMentionMenu {
                suggestionPanel {
                    ForEach(filteredMentions) { mention in
                        suggestionRow(
                            title: mention.title,
                            subtitle: mention.subtitle ?? mention.accessibilityLabel,
                            systemImage: suggestionIcon(for: mention.kind)
                        ) {
                            insertMention(mention)
                        }
                    }
                }
            }

            if showsSlashMenu {
                suggestionPanel {
                    ForEach(filteredSlashCommands) { command in
                        suggestionRow(
                            title: command.title,
                            subtitle: command.subtitle,
                            systemImage: command.systemImage
                        ) {
                            applyCommand(command.action)
                        }
                    }
                }
            }

            PasteHandlingTextInput(
                text: $text,
                placeholder: placeholder,
                highlightTerms: mentions.map { "@\($0.displayText)" },
                isFocused: isFocused,
                onPasteImage: { image in
                    onPasteImage?(image)
                }
            )
            .onChange(of: text) { _, newValue in
                updateSuggestions(for: newValue)
                pruneMissingMentions(from: newValue)
            }
        }
    }

    @ViewBuilder
    private func suggestionPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            content()
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

    private func suggestionRow(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.accentBlue)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppTheme.mutedText)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func updateSuggestions(for value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.split(whereSeparator: \.isWhitespace)

        if suppressSuggestionReopen {
            let lastToken = components.last ?? ""
            if lastToken.hasPrefix("@") || lastToken.hasPrefix("/") {
                showsMentionMenu = false
                showsSlashMenu = false
                return
            }

            suppressSuggestionReopen = false
        }

        guard let last = components.last else {
            showsMentionMenu = false
            showsSlashMenu = false
            preferredMentionKind = nil
            return
        }

        if last.hasPrefix("@") {
            activeMentionQuery = String(last.dropFirst())
            showsMentionMenu = true
            showsSlashMenu = false
            return
        }

        if last.hasPrefix("/") {
            activeSlashQuery = String(last.dropFirst())
            showsSlashMenu = true
            showsMentionMenu = false
            preferredMentionKind = nil
            return
        }

        showsMentionMenu = false
        showsSlashMenu = false
        preferredMentionKind = nil
    }

    private func insertMention(_ mention: RichInputMentionRef) {
        replaceActiveToken(with: "@\(mention.displayText) ")
        if !mentions.contains(mention) {
            mentions.append(mention)
        }
        showsMentionMenu = false
        preferredMentionKind = nil
        suppressSuggestionReopen = true
    }

    private func applyCommand(_ action: RichInputCommandAction) {
        onCommand?(action)

        switch action {
        case .signature:
            showsSlashMenu = false
            preferredMentionKind = nil
        case .insertMention(let kind):
            preferredMentionKind = kind
            replaceActiveToken(with: "@")
            showsSlashMenu = false
            showsMentionMenu = true
        default:
            replaceActiveToken(with: applyRichInputFormatting(action))
            showsSlashMenu = false
            preferredMentionKind = nil
        }
    }

    private func replaceActiveToken(with replacement: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.split(whereSeparator: \.isWhitespace)
        guard let last = components.last, last.hasPrefix("@") || last.hasPrefix("/") else {
            text += replacement
            return
        }

        if let range = text.range(of: String(last), options: .backwards) {
            text.replaceSubrange(range, with: replacement)
        } else {
            text += replacement
        }
    }

    private func pruneMissingMentions(from value: String) {
        mentions.removeAll { mention in
            !value.contains("@\(mention.displayText)")
        }
    }

    private func suggestionIcon(for kind: RichInputMentionKind) -> String {
        switch kind {
        case .task:
            return "checklist"
        case .thread:
            return "envelope"
        case .event:
            return "calendar"
        case .person:
            return "person.2"
        }
    }
}

/// UITextView wrapper that intercepts paste to detect images from the clipboard
/// and provides auto-formatting for markdown bullet lists.
struct PasteHandlingTextInput: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var highlightTerms: [String] = []
    var isFocused: Bool? = nil
    let onPasteImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, placeholder: placeholder, highlightTerms: highlightTerms, onPasteImage: onPasteImage)
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
        view.highlightTerms = highlightTerms

        // Show placeholder initially
        if text.isEmpty {
            view.text = placeholder
            view.textColor = UIColor.placeholderText
        } else {
            view.text = text
            view.textColor = UIColor.label
            context.coordinator.applyHighlights(to: view)
        }

        // Preserve the existing auto-focus behavior unless the parent explicitly controls focus.
        if isFocused ?? true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                view.becomeFirstResponder()
            }
        }
        return view
    }

    func updateUIView(_ uiView: PasteInterceptingTextView, context: Context) {
        context.coordinator.highlightTerms = highlightTerms
        uiView.highlightTerms = highlightTerms

        if let isFocused {
            if isFocused, !uiView.isFirstResponder {
                DispatchQueue.main.async {
                    uiView.becomeFirstResponder()
                }
            } else if !isFocused, uiView.isFirstResponder {
                DispatchQueue.main.async {
                    uiView.resignFirstResponder()
                }
            }
        }

        // Only sync when text is changed externally (e.g. after submit clears it)
        guard text != context.coordinator.lastKnownText else {
            context.coordinator.applyHighlights(to: uiView)
            return
        }
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
            context.coordinator.applyHighlights(to: uiView)
        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        let placeholder: String
        var highlightTerms: [String]
        let onPasteImage: (UIImage) -> Void
        /// Tracks the last text value the coordinator wrote to the binding,
        /// used to distinguish external (submit) clears from internal edits.
        var lastKnownText: String = ""

        init(
            text: Binding<String>,
            placeholder: String,
            highlightTerms: [String],
            onPasteImage: @escaping (UIImage) -> Void
        ) {
            _text = text
            self.placeholder = placeholder
            self.highlightTerms = highlightTerms
            self.onPasteImage = onPasteImage
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            // Replace placeholder with empty field on focus
            if textView.textColor == UIColor.placeholderText {
                textView.text = ""
                textView.textColor = UIColor.label
            }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText: String) -> Bool {
            guard textView.textColor != UIColor.placeholderText else { return true }

            let nsText = (textView.text ?? "") as NSString
            guard let mentionRange = mentionRangeIntersecting(range, in: nsText) else {
                return true
            }

            let updated = nsText.replacingCharacters(in: mentionRange, with: replacementText)
            textView.text = updated
            text = updated
            lastKnownText = updated
            applyHighlights(to: textView)
            textView.selectedRange = NSRange(location: mentionRange.location + (replacementText as NSString).length, length: 0)
            textView.invalidateIntrinsicContentSize()
            return false
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
            applyHighlights(to: textView)
            // Notify SwiftUI layout to re-measure height from intrinsicContentSize
            textView.invalidateIntrinsicContentSize()
        }

        func applyHighlights(to textView: UITextView) {
            guard textView.textColor != UIColor.placeholderText else { return }

            let currentText = textView.text ?? ""
            let selectedRange = textView.selectedRange
            let attributed = NSMutableAttributedString(string: currentText)
            attributed.addAttributes([
                .font: UIFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: UIColor.label,
            ], range: NSRange(location: 0, length: attributed.length))

            for term in highlightTerms where !term.isEmpty {
                let nsText = currentText as NSString
                var searchRange = NSRange(location: 0, length: nsText.length)

                while searchRange.location < nsText.length {
                    let found = nsText.range(of: term, options: [], range: searchRange)
                    guard found.location != NSNotFound else { break }

                    attributed.addAttributes([
                        .foregroundColor: UIColor.systemBlue,
                    ], range: found)

                    let nextLocation = found.location + found.length
                    searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
                }
            }

            textView.attributedText = attributed
            textView.selectedRange = selectedRange
            textView.setNeedsDisplay()
        }

        private func mentionRangeIntersecting(_ range: NSRange, in text: NSString) -> NSRange? {
            for term in highlightTerms where !term.isEmpty {
                var searchRange = NSRange(location: 0, length: text.length)

                while searchRange.location < text.length {
                    let found = text.range(of: term, options: [], range: searchRange)
                    guard found.location != NSNotFound else { break }

                    if NSIntersectionRange(found, range).length > 0
                        || (range.length == 0 && range.location > found.location && range.location <= found.location + found.length) {
                        return found
                    }

                    let nextLocation = found.location + found.length
                    searchRange = NSRange(location: nextLocation, length: text.length - nextLocation)
                }
            }

            return nil
        }
    }
}

// MARK: - PasteInterceptingTextView

/// UITextView subclass that intercepts paste to detect images from the clipboard.
/// Overrides intrinsicContentSize so SwiftUI's layout system drives height from content,
/// not from available space — keeping the composer at single-line until the user types.
final class PasteInterceptingTextView: UITextView {
    var onPasteImage: ((UIImage) -> Void)?
    var highlightTerms: [String] = []
    var mentionHighlightColor: UIColor = UIColor.systemBlue.withAlphaComponent(0.14)

    override var intrinsicContentSize: CGSize {
        // Measure the height required for the current content
        let measured = sizeThatFits(
            CGSize(width: frame.width > 0 ? frame.width : UIScreen.main.bounds.width,
                   height: .greatestFiniteMagnitude)
        )
        return CGSize(width: UIView.noIntrinsicMetric, height: max(measured.height, 20))
    }

    override func draw(_ rect: CGRect) {
        drawMentionHighlights()
        super.draw(rect)
    }

    private func drawMentionHighlights() {
        guard textColor != UIColor.placeholderText, !highlightTerms.isEmpty else { return }

        let nsText = (text ?? "") as NSString
        let inset = textContainerInset

        mentionHighlightColor.setFill()

        for term in highlightTerms where !term.isEmpty {
            var searchRange = NSRange(location: 0, length: nsText.length)

            while searchRange.location < nsText.length {
                let found = nsText.range(of: term, options: [], range: searchRange)
                guard found.location != NSNotFound else { break }

                let glyphRange = layoutManager.glyphRange(forCharacterRange: found, actualCharacterRange: nil)
                layoutManager.enumerateEnclosingRects(
                    forGlyphRange: glyphRange,
                    withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                    in: textContainer
                ) { rect, _ in
                    let pillRect = rect
                        .offsetBy(dx: inset.left, dy: inset.top)
                        .insetBy(dx: -5, dy: -2)
                    UIBezierPath(
                        roundedRect: pillRect,
                        cornerRadius: pillRect.height / 2
                    ).fill()
                }

                let nextLocation = found.location + found.length
                searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
            }
        }
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

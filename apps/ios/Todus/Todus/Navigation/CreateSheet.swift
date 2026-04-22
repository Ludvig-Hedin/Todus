import PhotosUI
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Universal create modal — shown as an in-app overlay (not a system sheet).
/// Merges the global type selector with CaptureComposer's attachments, voice, and slash commands.
struct CreateSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FolderRecord.createdAt) private var folders: [FolderRecord]

    /// Pre-selected type — set by the caller based on which tab/context opened the sheet.
    var initialType: CreateItemType = .auto
    @Binding var isPresented: Bool

    // MARK: - State

    @State private var text = ""
    @State private var selectedType: CreateItemType = .auto
    @State private var selectedFolder: FolderRecord? = nil
    @State private var selectedDate: Date? = nil
    @State private var isShowingDatePicker = false

    // Email-specific secondary fields
    @State private var recipientText = ""
    @State private var subjectText = ""

    // Event-specific secondary fields
    @State private var locationText = ""
    @State private var selectedEndDate: Date? = nil
    @State private var isShowingEndDatePicker = false

    // Attachment state (ported from CaptureComposer)
    @State private var isPickingAttachment = false
    @State private var isShowingFilePicker = false
    @State private var isShowingPhotoPicker = false
    @State private var isShowingCamera = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingAttachments: [String] = []

    // Slash command menu
    @State private var showsSlashMenu = false

    // Keyboard tracking — MainTabView uses .ignoresSafeArea(.keyboard),
    // so we manually push the composer above the keyboard.
    @StateObject private var keyboard = KeyboardObserver()

    private let attachButtonSize: CGFloat = 40

    var body: some View {
        ZStack(alignment: .bottom) {
            // Scrim — strong enough to clearly separate modal from background
            Color(UIColor(white: 0.06, alpha: 1)).opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 8) {
                // Slash menu floats above the input card
                if showsSlashMenu {
                    slashMenuPanel
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                inputArea
                typePill
            }
            .padding(.horizontal, 12)
            // Sit above the keyboard when visible, or above the tab bar (86pt).
            // max() avoids a conditional branch so SwiftUI doesn't create a
            // redundant layout pass when the keyboard height flickers to 0.
            .padding(.bottom, max(keyboard.height + 8, 86))
            .animation(.easeOut(duration: 0.25), value: keyboard.height)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        // Ignore both container and keyboard safe areas at the bottom so the
        // ZStack extends to the physical screen edge. The keyboard.height
        // padding above handles manual positioning — without this the overlay
        // gets pushed by keyboard avoidance AND by our own padding, putting the
        // composer at the top of the screen.
        .ignoresSafeArea(.all, edges: .bottom)
        .animation(.snappy(duration: 0.18), value: showsSlashMenu)
        .animation(.snappy(duration: 0.15), value: isPickingAttachment)
        .animation(.snappy(duration: 0.2), value: selectedType)
        .task {
            await services.captureService.syncSharedFolders(in: modelContext)
        }
        .onAppear {
            selectedType = initialType
            // Auto-set start date for events if none selected
            if initialType == .event, selectedDate == nil {
                selectedDate = Date()
                selectedEndDate = Date().addingTimeInterval(3600)
            }
        }
        .sheet(isPresented: $isShowingDatePicker) {
            datePickerSheet(isEndDate: false)
                .presentationDetents([.height(420)])
                .presentationDragIndicator(.visible)
                .presentationBackground(AppTheme.backgroundTop)
                .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        .sheet(isPresented: $isShowingEndDatePicker) {
            datePickerSheet(isEndDate: true)
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
                Task {
                    guard let filename = await AttachmentService.shared.importFile(at: url) else {
                        return
                    }
                    pendingAttachments.append(filename)
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
        // Keep end date at least as late as start date when start changes
        .onChange(of: selectedDate) { _, newStart in
            guard let newStart, let end = selectedEndDate, end < newStart else { return }
            selectedEndDate = newStart.addingTimeInterval(3600)
        }
        // Auto-populate end date when type switches to event
        .onChange(of: selectedType) { _, newType in
            if newType == .event, selectedDate == nil {
                selectedDate = Date()
                selectedEndDate = Date().addingTimeInterval(3600)
            }
        }
    }

    // MARK: - Input Area

    /// The main input region: attachment "+" button + input box with toolbar.
    /// Attachment picker panel floats above the "+" button when active.
    private var inputArea: some View {
        ZStack(alignment: .bottomLeading) {
            HStack(alignment: .bottom, spacing: 8) {
                // Attachment trigger — circle button (hidden for email; full compose handles attachments)
                if selectedType != .email {
                    Button {
                        withAnimation(.snappy(duration: 0.15)) { isPickingAttachment.toggle() }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppTheme.mutedText)
                            .frame(width: attachButtonSize, height: attachButtonSize)
                    }
                    .buttonStyle(.plain)
                    .background(AppTheme.surfacePrimary, in: Circle())
                    .overlay(Circle().stroke(AppTheme.strongBorder, lineWidth: 1))
                }

                // Main input box
                mainInputBox
            }

            // Attachment picker panel — floats above the "+" button
            if isPickingAttachment {
                attachmentPanel
                    .padding(.bottom, attachButtonSize + 8)
                    .transition(.scale(scale: 0.85, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
    }

    private var mainInputBox: some View {
        VStack(spacing: 0) {
            // Email: To + Subject fields above main body input
            if selectedType == .email {
                emailSecondaryFields
            }

            // Attachment thumbnails
            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingAttachments, id: \.self) { filename in
                            attachmentThumbnail(filename: filename)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.top, 10)
                .padding(.bottom, 2)
            }

            // Text input — matches AIChatView: maxHeight caps at 120px so the
            // sheet stays compact and SwiftUI layout doesn't grow unboundedly.
            PasteHandlingTextInput(
                text: $text,
                placeholder: placeholderText,
                isFocused: selectedType != .email,
                maxHeight: 120,
                onPasteImage: handlePastedImage
            )
            .frame(maxHeight: 120)
            .padding(.top, (pendingAttachments.isEmpty && selectedType != .email) ? 10 : 6)
            .padding(.bottom, selectedType == .event ? 2 : 4)
            .padding(.horizontal, 14)
            .onChange(of: text) { _, value in
                handleTextChange(value)
            }

            // Event: location field below main text
            if selectedType == .event {
                eventLocationField
            }

            // Toolbar: folder | date | spacer | voice | send
            toolbarRow
        }
        .background(
            AppTheme.surfacePrimary,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.strongBorder, lineWidth: 1)
        )
    }

    // MARK: - Secondary Fields

    /// Email-specific: To + Subject text fields rendered above the body input.
    private var emailSecondaryFields: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("To")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(width: 52, alignment: .trailing)
                TextField("recipient@example.com", text: $recipientText)
                    .font(.system(size: 14))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider()
                .opacity(0.25)
                .padding(.horizontal, 14)

            HStack(spacing: 6) {
                Text("Subject")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(width: 52, alignment: .trailing)
                TextField("Subject", text: $subjectText)
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider()
                .opacity(0.25)
                .padding(.horizontal, 14)
        }
        .padding(.top, 6)
    }

    /// Event-specific: location field rendered below the title input.
    private var eventLocationField: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.25)
                .padding(.horizontal, 14)

            HStack(spacing: 8) {
                Image(systemName: "location")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(width: 16)
                TextField("Location (optional)", text: $locationText)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }

    // MARK: - Toolbar

    private var toolbarRow: some View {
        HStack(spacing: 4) {
            // Folder selector — shown for task, auto, event
            if showsFolderPicker {
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
                .opacity(metadataControlOpacity)
            }

            // Date selector — shown for task, auto, event (as start time)
            if showsDatePicker {
                Button {
                    if selectedDate == nil {
                        selectedDate = selectedType == .event ? Date() : Date().addingTimeInterval(3600)
                    }
                    isShowingDatePicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: selectedDate == nil ? "clock" : "clock.fill")
                            .font(.system(size: 13, weight: .semibold))
                        if let date = selectedDate {
                            Text(selectedType == .event ? "Starts \(dateLabel(for: date))" : dateLabel(for: date))
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(selectedDate == nil ? AppTheme.mutedText : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        selectedDate != nil ? AppTheme.surfaceSecondary : Color.clear,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .opacity(metadataControlOpacity)
            }

            // End time — event only, shown once a start date is set
            if selectedType == .event, selectedDate != nil {
                Button {
                    if selectedEndDate == nil {
                        selectedEndDate = (selectedDate ?? Date()).addingTimeInterval(3600)
                    }
                    isShowingEndDatePicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: selectedEndDate == nil ? "clock.badge.checkmark" : "clock.badge.checkmark.fill")
                            .font(.system(size: 13, weight: .semibold))
                        if let end = selectedEndDate {
                            Text("Ends \(dateLabel(for: end))")
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                        } else {
                            Text("End time")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .foregroundStyle(selectedEndDate == nil ? AppTheme.mutedText : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        selectedEndDate != nil ? AppTheme.surfaceSecondary : Color.clear,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Voice transcription
            VoiceInputButton { transcribed in
                let current = text.trimmingCharacters(in: .whitespacesAndNewlines)
                text = current.isEmpty ? transcribed : current + " " + transcribed
            }

            // Send button
            let sendDisabled = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingAttachments.isEmpty
            Button(action: handleCreate) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
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

    // MARK: - Type Selector Pill

    private var typePill: some View {
        HStack(spacing: 0) {
            ForEach(CreateItemType.allCases) { type in
                Button {
                    withAnimation(.snappy(duration: 0.15)) { selectedType = type }
                } label: {
                    Image(systemName: type.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selectedType == type ? AppTheme.accentBlue : AppTheme.mutedText)
                        .frame(width: 50, height: 38)
                        .background(
                            selectedType == type ? AppTheme.accentBlue.opacity(0.12) : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(AppTheme.surfacePrimary, in: Capsule())
        .overlay(
            Capsule()
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Slash Menu

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

    // MARK: - Attachment Panel

    private var attachmentPanel: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.15)) { isPickingAttachment = false }
                isShowingPhotoPicker = true
            } label: { attachmentMenuRow(icon: "photo.on.rectangle", label: "Photo Library") }
            .buttonStyle(.plain)

            Divider().opacity(0.4)

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    withAnimation(.snappy(duration: 0.15)) { isPickingAttachment = false }
                    isShowingCamera = true
                } label: { attachmentMenuRow(icon: "camera", label: "Take Photo") }
                .buttonStyle(.plain)

                Divider().opacity(0.4)
            }

            Button {
                withAnimation(.snappy(duration: 0.15)) { isPickingAttachment = false }
                isShowingFilePicker = true
            } label: { attachmentMenuRow(icon: "doc.badge.plus", label: "Choose File") }
            .buttonStyle(.plain)
        }
        .frame(width: 200)
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 4)
    }

    private func attachmentMenuRow(icon: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    // MARK: - Attachment Thumbnail

    @ViewBuilder
    private func attachmentThumbnail(filename: String) -> some View {
        ZStack(alignment: .topTrailing) {
            if AttachmentService.shared.isImageFile(filename) {
                AttachmentThumbnailView(filename: filename, size: 52) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.surfaceSecondary)
                }
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.surfaceSecondary)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: "doc")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.mutedText)
                    )
            }
            Button {
                pendingAttachments.removeAll { $0 == filename }
                AttachmentService.shared.delete(filename: filename)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .background(Color.black.opacity(0.5), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(3)
        }
    }

    // MARK: - Date Picker Sheet

    private func datePickerSheet(isEndDate: Bool) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker(
                    isEndDate ? "End Time" : (selectedType == .event ? "Event Date" : "Due Date"),
                    selection: Binding(
                        get: {
                            isEndDate
                                ? (selectedEndDate ?? (selectedDate ?? Date()).addingTimeInterval(3600))
                                : (selectedDate ?? Date())
                        },
                        set: {
                            if isEndDate { selectedEndDate = $0 } else { selectedDate = $0 }
                        }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .padding(.horizontal, 16)

                if (isEndDate ? selectedEndDate : selectedDate) != nil {
                    Button(role: .destructive) {
                        if isEndDate {
                            selectedEndDate = nil
                            isShowingEndDatePicker = false
                        } else {
                            selectedDate = nil
                            isShowingDatePicker = false
                        }
                    } label: {
                        Label("Clear \(isEndDate ? "End Time" : "Date")", systemImage: "xmark.circle")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(AppTheme.danger)
                    .padding(.top, 12)
                }
            }
            .navigationTitle(isEndDate ? "Set End Time" : (selectedType == .event ? "Set Event Date" : "Set Due Date"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if isEndDate { isShowingEndDatePicker = false } else { isShowingDatePicker = false }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Computed Helpers

    private var placeholderText: String {
        switch selectedType {
        case .auto:  return "Write a task, event, or email…"
        case .task:  return "New Task"
        case .event: return "Event title"
        case .email: return "Message body…"
        }
    }

    private var metadataControlOpacity: Double {
        isSimpleCaptureFocus ? 0.68 : 1
    }

    private var isSimpleCaptureFocus: Bool {
        selectedType == .auto &&
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        pendingAttachments.isEmpty &&
        selectedFolder == nil &&
        selectedDate == nil
    }

    private var showsFolderPicker: Bool {
        selectedType == .auto || selectedType == .task || selectedType == .event
    }

    private var showsDatePicker: Bool {
        selectedType == .auto || selectedType == .task || selectedType == .event
    }

    // MARK: - Actions

    private func close() {
        withAnimation(.snappy(duration: 0.2)) {
            isPresented = false
        }
    }

    private func handleCreate() {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty || !pendingAttachments.isEmpty else { return }

        let resolvedType = selectedType == .auto ? resolveAutoType(for: input) : selectedType
        let attachments = pendingAttachments
        pendingAttachments = []
        // Don't reset folder/date — lets the user batch-capture to the same context
        text = ""

        Task {
            switch resolvedType {
            case .task:
                createTask(input, attachments: attachments)
            case .event:
                await createEvent(input, attachments: attachments)
            case .email:
                services.composeEmailSeedBody = input.isEmpty ? nil : input
                services.composeEmailSeedTo = recipientText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : recipientText.trimmingCharacters(in: .whitespacesAndNewlines)
                services.composeEmailSeedSubject = subjectText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : subjectText.trimmingCharacters(in: .whitespacesAndNewlines)
                services.showsComposeEmail = true
            case .auto:
                createTask(input, attachments: attachments)
            }
            close()
        }
    }

    private func createTask(_ input: String, attachments: [String] = []) {
        services.captureService.capture(
            rawComposerText: input,
            attachmentNames: attachments,
            selectedFolder: selectedFolder,
            overrideDueDate: selectedDate,
            in: modelContext
        )
    }

    private func createEvent(_ input: String, attachments: [String]) async {
        let startDate = selectedDate ?? Date()
        let endDate = selectedEndDate ?? startDate.addingTimeInterval(3600)
        let hasAccess: Bool
        if services.calendarService.canCreateEvents() {
            hasAccess = true
        } else {
            hasAccess = await services.calendarService.requestAccess()
        }

        guard hasAccess else {
            createTask(input, attachments: attachments)
            return
        }

        do {
            try await services.calendarService.createEvent(
                title: input,
                startDate: startDate,
                endDate: endDate,
                folderID: selectedFolder?.id
            )
        } catch {
            createTask(input, attachments: attachments)
        }
    }

    private func resolveAutoType(for input: String) -> CreateItemType {
        if detectDate(in: input) != nil { return .event }
        let lower = input.lowercased()
        if lower.contains("mail") || lower.contains("email") || lower.contains("reply") {
            return .email
        }
        return .task
    }

    private func detectDate(in text: String) -> Date? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(location: 0, length: text.utf16.count)
        return detector?.matches(in: text, options: [], range: range).first?.date
    }

    private func dateLabel(for date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    // MARK: - Slash Command Handling

    private func handleTextChange(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        withAnimation(.snappy(duration: 0.15)) {
            showsSlashMenu = trimmed.hasSuffix("/") && !trimmed.isEmpty
        }
    }

    private func applySlashAction(_ action: RichInputCommandAction) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("/") {
            let withoutSlash = String(trimmed.dropLast())
            text = withoutSlash.trimmingCharacters(in: .whitespaces)
        }
        switch action {
        case .dueToday:
            setDueDateToToday()
        case .dueTomorrow:
            setDueDateToTomorrow()
        case .dueNextWeek:
            setDueDateToNextWeek()
        case .inOneHour:
            selectedDate = Date().addingTimeInterval(3600)
        default:
            break
        }
        withAnimation(.snappy(duration: 0.18)) {
            showsSlashMenu = false
        }
    }

    private func slashActionColor(for action: RichInputCommandAction) -> Color {
        switch action {
        case .dueToday:     return .orange
        case .dueTomorrow:  return .blue
        case .dueNextWeek:  return .purple
        case .inOneHour:    return .green
        default:            return AppTheme.mutedText
        }
    }

    private func setDueDateToToday() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        selectedDate = cal.date(byAdding: .hour, value: 23, to: today) ?? today
    }

    private func setDueDateToTomorrow() {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: start) ?? start
        selectedDate = cal.date(byAdding: .hour, value: 9, to: tomorrow) ?? tomorrow
    }

    private func setDueDateToNextWeek() {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let nextWeek = cal.date(byAdding: .day, value: 7, to: start) ?? start
        selectedDate = cal.date(byAdding: .hour, value: 9, to: nextWeek) ?? nextWeek
    }

    // MARK: - Image Paste Handler

    private func handlePastedImage(_ image: UIImage) {
        if let filename = AttachmentService.shared.saveImage(image) {
            pendingAttachments.append(filename)
        }
    }
}

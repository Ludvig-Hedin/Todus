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
    @State private var ccText = ""
    @State private var bccText = ""
    @State private var subjectText = ""
    @State private var showEmailCcBcc = false
    @State private var fromConnectionId: String? = nil

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
    /// Attachment awaiting delete confirmation before its disk file is removed — nil hides
    /// the dialog. Mirrors `TaskDetailSheet.pendingDeleteAttachment`.
    @State private var pendingDeleteAttachment: String?

    // Slash command menu
    @State private var showsSlashMenu = false

    /// Surfaced when calendar permission is denied or EventKit save fails so
    /// the user can choose between saving as a task and dismissing — instead
    /// of having a phantom task silently appear.
    @State private var eventSaveFallbackPrompt: EventSaveFallback? = nil

    /// Guards the send button from double-fires while `handleCreate`'s async work is in
    /// flight — without this, a double-tap during the create Task could create duplicate
    /// tasks/events. Reset when the sheet closes or the fallback prompt fires (both are
    /// terminal states for the in-flight attempt).
    @State private var isSending = false

    private struct EventSaveFallback: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let saveAsTask: () -> Void
    }

    // Keyboard tracking — MainTabView uses .ignoresSafeArea(.keyboard),
    // so we manually push the composer above the keyboard.
    @StateObject private var keyboard = KeyboardObserver()
    /// Captured safe-area inset bottom so the composer can fall back to a sane
    /// position on iPad split-view / external-keyboard layouts where
    /// `keyboardFrameEndUserInfoKey` reports zero height but the system still has
    /// a docked keyboard region. We can't rely on `keyboard.height` alone there.
    @State private var capturedSafeAreaBottom: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            // Progressive blur scrim — fully transparent at the top, building to a
            // heavy blur + dim behind the modal. A gradient mask gives the bottom-up
            // falloff so content above the composer stays legible.
            progressiveBlurScrim
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 8) {
                // Slash menu floats above the input card
                if showsSlashMenu {
                    slashMenuPanel
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Attachment picker panel — floats above the input box and is
                // anchored to the bottom-leading where the in-toolbar attach
                // button lives.
                if isPickingAttachment {
                    HStack(spacing: 0) {
                        attachmentPanel
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 4)
                    .transition(.scale(scale: 0.9, anchor: .bottomLeading).combined(with: .opacity))
                }

                mainInputBox

                typePill
            }
            .padding(.horizontal, 12)
            // Sit above the keyboard when visible, or above the tab bar (86pt).
            // max() avoids a conditional branch so SwiftUI doesn't create a
            // redundant layout pass when the keyboard height flickers to 0.
            // On iPad split-view / external keyboard cases where `keyboard.height`
            // can briefly read 0 mid-resize, the safe-area inset bottom is the next
            // best guess for how much space the system is reserving below us.
            .padding(.bottom, max(keyboard.height + 8, capturedSafeAreaBottom + 8, 86))
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: keyboard.height)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { capturedSafeAreaBottom = proxy.safeAreaInsets.bottom }
                        .onChange(of: proxy.safeAreaInsets.bottom) { _, newValue in
                            capturedSafeAreaBottom = newValue
                        }
                }
            )
        }
        // Ignore both container and keyboard safe areas at the bottom so the
        // ZStack extends to the physical screen edge. The keyboard.height
        // padding above handles manual positioning — without this the overlay
        // gets pushed by keyboard avoidance AND by our own padding, putting the
        // composer at the top of the screen.
        .ignoresSafeArea([.container, .keyboard], edges: .bottom)
        .animation(.snappy(duration: 0.18), value: showsSlashMenu)
        .animation(.snappy(duration: 0.15), value: isPickingAttachment)
        .animation(.snappy(duration: 0.2), value: selectedType)
        .task {
            await services.captureService.syncSharedFolders(in: modelContext)
        }
        .onAppear {
            selectedType = initialType
            fromConnectionId = services.connectionsService.connections.first?.id
            // Auto-set start date for events if none selected
            if initialType == .event, selectedDate == nil {
                selectedDate = Date()
                selectedEndDate = Date().addingTimeInterval(3600)
            }
        }
        .sheet(isPresented: $isShowingDatePicker) {
            datePickerSheet(isEndDate: false)
                .presentationDetents([.height(520)])
                .presentationDragIndicator(.visible)
                .appSheetBackground()
                .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        .sheet(isPresented: $isShowingEndDatePicker) {
            datePickerSheet(isEndDate: true)
                .presentationDetents([.height(520)])
                .presentationDragIndicator(.visible)
                .appSheetBackground()
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
        // Symmetric guard: if the user drags the end picker before the start, snap it
        // forward to start + 1h so they don't have to back-track. Validation still runs
        // in `handleCreate` to catch the rare case where they actively confirm an
        // invalid range via the date picker `Done` button.
        .onChange(of: selectedEndDate) { _, newEnd in
            guard let newEnd, let start = selectedDate, newEnd <= start else { return }
            selectedEndDate = start.addingTimeInterval(3600)
        }
        // Auto-populate end date when type switches to event
        .onChange(of: selectedType) { _, newType in
            if newType == .event, selectedDate == nil {
                selectedDate = Date()
                selectedEndDate = Date().addingTimeInterval(3600)
            }
        }
        .alert(item: $eventSaveFallbackPrompt) { fallback in
            Alert(
                title: Text(fallback.title),
                message: Text(fallback.message),
                primaryButton: .default(Text("Save as task")) {
                    fallback.saveAsTask()
                },
                secondaryButton: .cancel(Text("Dismiss"))
            )
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
                if let filename = pendingDeleteAttachment {
                    pendingAttachments.removeAll { $0 == filename }
                    AttachmentService.shared.delete(filename: filename)
                }
                pendingDeleteAttachment = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteAttachment = nil
            }
        }
    }

    // MARK: - Scrim

    /// Progressive blur: stacked materials with cascading gradient masks so blur
    /// intensity ramps up smoothly from clear at the top to a heavy, opaque
    /// frost behind the composer. Three layers — light → medium → heavy — each
    /// kicking in further down the screen — produce a true gradient blur rather
    /// than a single flat blur with a fade.
    private var progressiveBlurScrim: some View {
        ZStack {
            // Layer 1 — gentle haze starting around mid-screen
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear,               location: 0.00),
                            .init(color: .clear,               location: 0.20),
                            .init(color: .black.opacity(0.6),  location: 0.45),
                            .init(color: .black,               location: 0.65),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Layer 2 — stronger blur taking over in the lower half
            Rectangle()
                .fill(.thinMaterial)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear,               location: 0.00),
                            .init(color: .clear,               location: 0.35),
                            .init(color: .black.opacity(0.7),  location: 0.60),
                            .init(color: .black,               location: 0.80),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Layer 3 — heavy frost concentrated behind the composer
            Rectangle()
                .fill(.ultraThickMaterial)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear,               location: 0.00),
                            .init(color: .clear,               location: 0.50),
                            .init(color: .black.opacity(0.8),  location: 0.72),
                            .init(color: .black,               location: 0.88),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Dim wash — heavier so the modal stands out from content behind it.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.00), location: 0.00),
                    .init(color: .black.opacity(0.20), location: 0.30),
                    .init(color: .black.opacity(0.45), location: 0.65),
                    .init(color: .black.opacity(0.65), location: 1.00),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(true)
    }

    // MARK: - Input Box

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
            // isFocused: nil — the view auto-focuses once in makeUIView and then
            // manages its own responder state. Passing a Bool here made updateUIView
            // call becomeFirstResponder on every render, stealing focus from the
            // To/Subject/Location TextFields when tapped.
            PasteHandlingTextInput(
                text: $text,
                placeholder: placeholderText,
                isFocused: nil,
                maxHeight: 120,
                onPasteImage: handlePastedImage
            )
            .frame(maxHeight: 120)
            .padding(.top, (pendingAttachments.isEmpty && selectedType != .email) ? 12 : 8)
            .padding(.bottom, 2)
            .padding(.horizontal, 16)
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
        // Collapse to content height. Has to live before .background so the
        // background/border resize with the box rather than locking it open.
        .fixedSize(horizontal: false, vertical: true)
        .background(
            AppTheme.surfacePrimary,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.composer, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.composer, style: .continuous)
                .stroke(AppTheme.strongBorder, lineWidth: 1)
        )
    }

    // MARK: - Secondary Fields

    /// Email-specific: To + CC/BCC + Subject + formatting toolbar, rendered above the body input.
    private var emailSecondaryFields: some View {
        VStack(spacing: 0) {
            fromEmailRow

            // To row with CC/BCC chevron
            HStack(spacing: 6) {
                Text("To")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(width: 52, alignment: .trailing)
                TextField("", text: $recipientText, prompt: Text("Add recipients").foregroundStyle(AppTheme.mutedText))
                    .font(.system(size: 14))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showEmailCcBcc.toggle() }
                } label: {
                    Image(systemName: showEmailCcBcc ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.mutedText)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            // CC + BCC rows — revealed by chevron
            if showEmailCcBcc {
                Divider().opacity(0.25).padding(.horizontal, 14)
                HStack(spacing: 6) {
                    Text("Cc")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.mutedText)
                        .frame(width: 52, alignment: .trailing)
                    TextField("", text: $ccText, prompt: Text("Add Cc recipients").foregroundStyle(AppTheme.mutedText))
                        .font(.system(size: 14))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)

                Divider().opacity(0.25).padding(.horizontal, 14)
                HStack(spacing: 6) {
                    Text("Bcc")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.mutedText)
                        .frame(width: 52, alignment: .trailing)
                    TextField("", text: $bccText, prompt: Text("Add Bcc recipients").foregroundStyle(AppTheme.mutedText))
                        .font(.system(size: 14))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }

            Divider().opacity(0.25).padding(.horizontal, 14)

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

            Divider().opacity(0.25).padding(.horizontal, 14)

            // Compact formatting toolbar
            emailFormattingToolbar

            Divider().opacity(0.25).padding(.horizontal, 14)
        }
        .padding(.top, 6)
    }

    /// From account row — only shown when user has multiple connected email accounts.
    /// Mirrors EmailComposeView.fromRow but drives `fromConnectionId` local state.
    @ViewBuilder
    private var fromEmailRow: some View {
        let connections = services.connectionsService.connections
        if connections.count > 1 {
            HStack(spacing: 6) {
                Text("From")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(width: 52, alignment: .trailing)
                Menu {
                    ForEach(connections, id: \.id) { account in
                        Button {
                            fromConnectionId = account.id
                        } label: {
                            if fromConnectionId == account.id {
                                Label(account.email, systemImage: "checkmark")
                            } else {
                                Text(account.email)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(connections.first(where: { $0.id == fromConnectionId })?.email
                            ?? connections.first?.email
                            ?? "Loading…")
                            .font(.system(size: 14))
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppTheme.mutedText)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider().opacity(0.25).padding(.horizontal, 14)
        }
    }

    private var emailFormattingToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                emailFormatButton(icon: "bold") { insertEmailFormat("**", closing: "**", placeholder: "bold text") }
                emailFormatButton(icon: "italic") { insertEmailFormat("_", closing: "_", placeholder: "italic text") }
                emailFormatDivider()
                emailFormatButton(icon: "textformat.size.larger") { insertEmailLinePrefix("# ") }
                emailFormatButton(icon: "textformat.size") { insertEmailLinePrefix("## ") }
                emailFormatDivider()
                emailFormatButton(icon: "list.bullet") { insertEmailLinePrefix("• ") }
                emailFormatButton(icon: "list.number") { insertEmailLinePrefix("1. ") }
                emailFormatButton(icon: "checklist") { insertEmailLinePrefix("☐ ") }
                emailFormatDivider()
                emailFormatButton(icon: "quote.opening") { insertEmailLinePrefix("> ") }
                emailFormatButton(icon: "minus") { insertEmailLinePrefix("---") }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private func emailFormatButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func emailFormatDivider() -> some View {
        Rectangle()
            .fill(AppTheme.divider)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 3)
    }

    private func insertEmailFormat(_ opening: String, closing: String, placeholder: String) {
        let newline = text.isEmpty || text.hasSuffix("\n") ? "" : "\n"
        text += "\(newline)\(opening)\(placeholder)\(closing)"
    }

    private func insertEmailLinePrefix(_ prefix: String) {
        let newline = text.isEmpty || text.hasSuffix("\n") ? "" : "\n"
        text += "\(newline)\(prefix)"
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
            // Attachment trigger — leftmost on every mode so attachments are
            // discoverable for tasks, events, and emails alike.
            Button {
                withAnimation(.snappy(duration: 0.15)) { isPickingAttachment.toggle() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isPickingAttachment ? AppTheme.accentBlue : AppTheme.mutedText)
                    .frame(width: 28, height: 28)
                    .background(
                        isPickingAttachment ? AppTheme.accentBlue.opacity(0.14) : Color.clear,
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPickingAttachment ? "Close attachment picker" : "Add attachment")

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
                        Image(systemName: selectedDate == nil ? "calendar" : "calendar.badge.clock")
                            .font(.system(size: 13, weight: .semibold))
                        if let date = selectedDate {
                            Text(compactDateLabel(for: date))
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
                        Image(systemName: selectedEndDate == nil ? "flag" : "flag.fill")
                            .font(.system(size: 13, weight: .semibold))
                        if let end = selectedEndDate {
                            Text(compactDateLabel(for: end))
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                        } else {
                            Text("End")
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
            // Email additionally requires a non-empty To — otherwise Send silently no-ops
            // downstream in ComposeEmail with nothing to address the message to.
            let missingRecipient = selectedType == .email
                && recipientText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let sendDisabled = (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingAttachments.isEmpty)
                || missingRecipient
            Button(action: handleCreate) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(AppPrimaryButtonStyle())
            .clipShape(Circle())
            .disabled(sendDisabled || isSending)
            .opacity(sendDisabled ? 0.4 : 1)
            .animation(.easeOut(duration: 0.12), value: sendDisabled)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: - Type Selector Pill

    private var typePill: some View {
        HStack(spacing: 2) {
            ForEach(CreateItemType.allCases) { type in
                typePillButton(for: type)
            }
        }
        .padding(3)
        .background(AppTheme.surfacePrimary, in: Capsule())
        .overlay(Capsule().stroke(AppTheme.cardBorder, lineWidth: 1))
    }

    @ViewBuilder
    private func typePillButton(for type: CreateItemType) -> some View {
        let isSelected = selectedType == type
        Button {
            withAnimation(.snappy(duration: 0.2)) { selectedType = type }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: type.icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(type.title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isSelected ? AppTheme.accentBlue : AppTheme.mutedText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected ? AppTheme.accentBlue.opacity(0.14) : Color.clear,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
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
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
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
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous).stroke(AppTheme.cardBorder, lineWidth: 1))
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
                    RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                        .fill(AppTheme.surfaceSecondary)
                }
            } else {
                RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                    .fill(AppTheme.surfaceSecondary)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: "doc")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.mutedText)
                    )
            }
            Button {
                pendingDeleteAttachment = filename
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
                    // Clearing a date is reversible — using `.destructive` painted this
                    // row red, framing it like "delete event" to users. Secondary tint
                    // is the right semantic weight for an undo-able choice.
                    Button {
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
                    .tint(.secondary)
                    .foregroundStyle(.secondary)
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
        case .task:  return "Create a task…"
        case .event: return "Create an event…"
        case .email: return "Create an email…"
        }
    }

    private var metadataControlOpacity: Double {
        isSimpleCaptureFocus ? 0.68 : 1
    }

    private var isSimpleCaptureFocus: Bool { false }

    private var showsFolderPicker: Bool {
        selectedType == .task || selectedType == .event || selectedType == .auto
    }

    private var showsDatePicker: Bool {
        selectedType == .task || selectedType == .event || selectedType == .auto
    }

    // MARK: - Actions

    private func close() {
        isSending = false
        withAnimation(.spring(response: 0.25, dampingFraction: 0.95)) {
            isPresented = false
        }
    }

    private func handleCreate() {
        guard !isSending else { return }
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty || !pendingAttachments.isEmpty else { return }

        // Small confirmation haptic on send — matches AI chat send + the iOS Mail
        // send affordance so the action feels like a deliberate dispatch rather
        // than a silent tap.
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Guard: an event whose end-date is before its start-date is almost always
        // an accidental picker drag (user adjusts start past the prior end). Surface
        // an inline alert and bail before any IO happens — the picker stays open via
        // the eventSaveFallbackPrompt mechanism so the user can correct without losing
        // their other field values.
        if selectedType == .event,
           let start = selectedDate,
           let end = selectedEndDate,
           end <= start {
            eventSaveFallbackPrompt = EventSaveFallback(
                title: "End time is before start",
                message: "The event ends at or before it begins. Adjust the end time and try again.",
                // No save-as-task fallback for a malformed range — the user just needs to fix the date.
                saveAsTask: {}
            )
            return
        }

        let attachments = pendingAttachments
        pendingAttachments = []
        text = ""
        isSending = true

        Task {
            // In auto mode: check for compound intents first (e.g. "Träffa Johan kl 13 imorgon och maila honom presentationen innan")
            if selectedType == .auto, !input.isEmpty {
                let intents = CompoundIntentParser.parse(text: input, now: .now, locale: .current, timeZone: .current)
                if intents.count > 1 {
                    // Contract (B-035): each sub-intent keeps its OWN parsed date.
                    // `intent.date` is produced per-segment by CompoundIntentParser (including
                    // anchor/relative resolution like "innan"/"before"), so the `?? selectedDate`
                    // fallback only fires for sub-intents that parsed no date of their own — it is
                    // NOT a single shared date applied across every intent.
                    for (index, intent) in intents.enumerated() {
                        let itemAttachments = index == 0 ? attachments : []
                        switch intent.type {
                        case .event:
                            await createEvent(intent.title, startDate: intent.date, attachments: itemAttachments)
                            // If event creation failed (permission denied / EventKit error),
                            // createEvent set eventSaveFallbackPrompt and returned. Stop here so
                            // we don't keep creating the remaining intents and then close() the
                            // sheet out from under the alert the user still needs to act on.
                            if eventSaveFallbackPrompt != nil {
                                isSending = false
                                return
                            }
                        case .task:
                            createTask(intent.title, dueDate: intent.date ?? selectedDate, attachments: itemAttachments)
                        case .email:
                            if !services.showsComposeEmail {
                                services.composeEmailSeedBody = intent.title
                                services.composeEmailSeedAttachments = itemAttachments
                                services.composeEmailSeedFromConnectionId = fromConnectionId
                                services.showsComposeEmail = true
                            }
                        }
                    }
                    close()
                    return
                }
            }

            // Single intent — use NLP-parsed date when no explicit date was selected
            let parsed = selectedType == .auto || selectedType == .event
                ? LocalTaskParsingService.parseImmediate(rawText: input, now: .now, locale: .current, timeZone: .current)
                : nil

            let resolvedType = selectedType == .auto ? resolveAutoType(for: input) : selectedType

            switch resolvedType {
            case .task:
                createTask(input, attachments: attachments)
            case .event:
                // Use NLP-parsed date when no date was explicitly picked
                let eventStart = selectedDate ?? parsed?.dueDate
                let eventTitle = selectedType == .auto ? (parsed?.title ?? input) : input
                await createEvent(eventTitle, startDate: eventStart, attachments: attachments)
                // createEvent may set eventSaveFallbackPrompt on failure (permission denied or
                // EventKit error). If it did, keep the sheet open so the alert can render.
                if eventSaveFallbackPrompt != nil {
                    isSending = false
                    return
                }
            case .email:
                services.composeEmailSeedBody = input.isEmpty ? nil : input
                services.composeEmailSeedTo = recipientText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : recipientText.trimmingCharacters(in: .whitespacesAndNewlines)
                services.composeEmailSeedCc = ccText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : ccText.trimmingCharacters(in: .whitespacesAndNewlines)
                services.composeEmailSeedBcc = bccText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : bccText.trimmingCharacters(in: .whitespacesAndNewlines)
                services.composeEmailSeedSubject = subjectText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : subjectText.trimmingCharacters(in: .whitespacesAndNewlines)
                services.composeEmailSeedAttachments = attachments
                services.composeEmailSeedFromConnectionId = fromConnectionId
                services.showsComposeEmail = true
            case .auto:
                createTask(input, attachments: attachments)
            }
            close()
        }
    }

    private func createTask(_ input: String, dueDate: Date? = nil, attachments: [String] = []) {
        services.captureService.capture(
            rawComposerText: input,
            attachmentNames: attachments,
            selectedFolder: selectedFolder,
            overrideDueDate: dueDate ?? selectedDate,
            in: modelContext
        )
    }

    private func createEvent(_ input: String, startDate: Date?, attachments: [String]) async {
        let startDate = startDate ?? Date()
        let endDate = selectedEndDate ?? startDate.addingTimeInterval(3600)
        let hasAccess: Bool
        if services.calendarService.canCreateEvents() {
            hasAccess = true
        } else {
            hasAccess = await services.calendarService.requestAccess()
        }

        guard hasAccess else {
            // Don't silently produce a task the user didn't ask for. Surface
            // the permission state and let them choose.
            eventSaveFallbackPrompt = EventSaveFallback(
                title: "Calendar access denied",
                message: "Todus can't add calendar events without permission. You can save this as a task instead, or grant access in Settings.",
                saveAsTask: { createTask(input, attachments: attachments) }
            )
            return
        }

        let trimmedLocation = locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await services.calendarService.createEvent(
                title: input,
                startDate: startDate,
                endDate: endDate,
                folderID: selectedFolder?.id,
                location: trimmedLocation.isEmpty ? nil : trimmedLocation,
                attachmentFilenames: attachments
            )
        } catch {
            eventSaveFallbackPrompt = EventSaveFallback(
                title: "Couldn't save event",
                message: (error as NSError).localizedDescription,
                saveAsTask: { createTask(input, attachments: attachments) }
            )
        }
    }

    private func resolveAutoType(for input: String) -> CreateItemType {
        let lower = input.lowercased()
        // Email keywords
        if lower.contains("mail") || lower.contains("email") || lower.contains("reply") {
            return .email
        }
        // Classify as event only when event-like keywords are present alongside a time/date reference
        let eventKeywords = [
            "träffa", "träff", "möt", "möte", "lunch", "middag", "frukost",
            "dejt", "fika", "mingel", "samtal", "presentation", "konferens",
            "intervju", "meet", "meeting", "dinner", "breakfast", "coffee", "call with",
        ]
        let hasEventKeyword = eventKeywords.contains(where: lower.contains)
        let parsed = LocalTaskParsingService.parseImmediate(rawText: input, now: .now, locale: .current, timeZone: .current)
        // Event when an event-like keyword sits next to any date/time reference…
        if hasEventKeyword && parsed.dueDate != nil { return .event }
        // …or when the input carries BOTH a date AND a specific time-of-day, even without a
        // keyword: a timed thing ("Dentist Tuesday 2pm") is an appointment. A date with no
        // time ("Pay rent Friday") stays a task — that's a deadline, not an event. (B-036.)
        if parsed.dueDate != nil && parsed.hasTime { return .event }
        return .task
    }

    private func dateLabel(for date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private func compactDateLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
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
        case .dueTomorrow:  return .primary
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
        // Honor the user's configured workday start so an early bird or a late starter
        // doesn't get a 9 AM reminder that doesn't match their actual schedule.
        let hour = workdayStartHour
        selectedDate = cal.date(byAdding: .hour, value: hour, to: tomorrow) ?? tomorrow
    }

    private func setDueDateToNextWeek() {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let nextWeek = cal.date(byAdding: .day, value: 7, to: start) ?? start
        let hour = workdayStartHour
        selectedDate = cal.date(byAdding: .hour, value: hour, to: nextWeek) ?? nextWeek
    }

    /// User's configured workday start hour (0–23). Falls back to 9 when the policy
    /// returns something out of range so a corrupted preference can't produce an
    /// invalid Calendar query.
    private var workdayStartHour: Int {
        let raw = services.assistantAutomationPolicy.workdayStartHour
        return (0...23).contains(raw) ? raw : 9
    }

    // MARK: - Image Paste Handler

    private func handlePastedImage(_ image: UIImage) {
        if let filename = AttachmentService.shared.saveImage(image) {
            pendingAttachments.append(filename)
        }
    }
}

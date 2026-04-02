import SwiftUI
import SwiftData

/// Universal create modal for macOS — adapts fields by selected type.
/// Mirrors the iOS CreateSheet but with desktop-optimized layout.
struct MacCreateSheet: View {
    @Environment(MacAppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FolderRecord.createdAt) private var folders: [FolderRecord]

    let defaultType: CreateItemType

    @State private var text = ""
    @State private var selectedType: CreateItemType = .auto
    @State private var selectedFolder: FolderRecord? = nil
    @State private var selectedDate: Date? = nil
    @State private var isShowingDatePicker = false
    @FocusState private var isFocused: Bool

    /// Callback to open email compose with seed body
    var onComposeEmail: ((String) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .font(.system(size: 13, weight: .medium))
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(MacTheme.spacing16)

            Divider().opacity(0.3)

            // Type selector pill bar
            typePicker
                .padding(.horizontal, MacTheme.spacing16)
                .padding(.top, MacTheme.spacing12)

            // Input area
            VStack(alignment: .leading, spacing: MacTheme.spacing8) {
                // Context-specific controls (folder, date)
                HStack(spacing: MacTheme.spacing8) {
                    if showsFolderPicker {
                        folderPicker
                    }
                    if showsDatePicker {
                        datePicker
                    }
                    Spacer()
                }

                // Text input
                TextField(placeholderText, text: $text, axis: .vertical)
                    .font(.system(size: 18, weight: .semibold))
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isFocused)
            }
            .padding(MacTheme.spacing16)

            Spacer()

            // Footer with create button
            HStack {
                Spacer()
                Button(action: handleCreate) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Create \(resolvedTypeName)")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, MacTheme.spacing16)
                    .padding(.vertical, MacTheme.spacing8)
                    .background(MacTheme.accent, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(MacTheme.spacing16)
        }
        .frame(minWidth: 420, minHeight: 280)
        .onAppear {
            selectedType = defaultType
            if defaultType == .event {
                selectedDate = Date()
            }
            isFocused = true
        }
        .task {
            do {
                try await services.syncSharedFolders(in: modelContext)
            } catch {
                print("[MacCreateSheet] Failed to sync shared folders: \(error)")
            }
        }
    }

    // MARK: - Type Picker

    private var typePicker: some View {
        HStack(spacing: 2) {
            ForEach(CreateItemType.allCases) { type in
                Button {
                    withAnimation(.snappy(duration: 0.15)) { selectedType = type }
                    if type == .event && selectedDate == nil {
                        selectedDate = Date()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: type.icon)
                            .font(.system(size: 12, weight: .medium))
                        Text(type.title)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(selectedType == type ? MacTheme.accent : MacTheme.textSecondary)
                    .padding(.horizontal, MacTheme.spacing12)
                    .padding(.vertical, MacTheme.spacing6)
                    .background(
                        selectedType == type ? MacTheme.accent.opacity(0.1) : Color.clear,
                        in: Capsule(style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: MacTheme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius)
                .stroke(MacTheme.cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Pickers

    private var folderPicker: some View {
        Menu {
            Button {
                selectedFolder = nil
            } label: {
                Label("Inbox", systemImage: "tray")
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
                    .font(.system(size: 11, weight: .medium))
                Text(selectedFolder?.name ?? "Inbox")
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(MacTheme.textSecondary)
            .padding(.horizontal, MacTheme.spacing8)
            .padding(.vertical, MacTheme.spacing4)
            .background(MacTheme.surfaceCard, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(MacTheme.cardBorder, lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
    }

    private var datePicker: some View {
        Button {
            if selectedDate == nil { selectedDate = Date().addingTimeInterval(3600) }
            isShowingDatePicker.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .medium))
                if let date = selectedDate {
                    Text(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                        .font(.system(size: 12, weight: .medium))
                } else {
                    Text("Pick date")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .foregroundStyle(MacTheme.textSecondary)
            .padding(.horizontal, MacTheme.spacing8)
            .padding(.vertical, MacTheme.spacing4)
            .background(MacTheme.surfaceCard, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(MacTheme.cardBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingDatePicker) {
            VStack {
                DatePicker(
                    selectedType == .event ? "Event Date" : "Due Date",
                    selection: Binding(
                        get: { selectedDate ?? Date() },
                        set: { selectedDate = $0 }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .padding()

                if selectedDate != nil {
                    Button("Clear Date", role: .destructive) {
                        selectedDate = nil
                        isShowingDatePicker = false
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.bottom, 12)
                }
            }
            .frame(width: 300)
        }
    }

    // MARK: - Helpers

    private var placeholderText: String {
        switch selectedType {
        case .auto:  return "Write anything..."
        case .task:  return "New Task"
        case .event: return "New Event"
        case .email: return "New Email"
        }
    }

    private var resolvedTypeName: String {
        let type = selectedType == .auto ? resolveAutoType(for: text) : selectedType
        return type.title
    }

    private var showsFolderPicker: Bool {
        selectedType == .auto || selectedType == .task || selectedType == .event
    }

    private var showsDatePicker: Bool {
        selectedType == .auto || selectedType == .task || selectedType == .event
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

    private func handleCreate() {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        let resolvedType = selectedType == .auto ? resolveAutoType(for: input) : selectedType

        switch resolvedType {
        case .task:
            createTask(input)
        case .event:
            Task { await createEvent(input) }
        case .email:
            onComposeEmail?(input)
        case .auto:
            createTask(input)
        }
        dismiss()
    }

    private func createTask(_ input: String) {
        let task = TaskRecord(
            rawInput: input,
            title: input,
            dueDate: selectedDate,
            folder: selectedFolder
        )
        modelContext.insert(task)
        try? modelContext.save()
    }

    private func createEvent(_ input: String) async {
        let startDate = selectedDate ?? Date()
        let hasAccess: Bool
        if services.calendarService.canReadEvents() {
            hasAccess = true
        } else {
            hasAccess = await services.calendarService.requestAccess()
        }

        guard hasAccess else {
            // Fallback to task so the input is never lost
            createTask(input)
            return
        }

        do {
            try await services.calendarService.createEvent(
                title: input,
                startDate: startDate,
                endDate: startDate.addingTimeInterval(3600),
                folderID: selectedFolder?.id
            )
        } catch {
            // Fallback to task
            createTask(input)
        }
    }
}

import SwiftUI
import SwiftData

/// Universal create modal — shown as an in-app overlay (not a system sheet).
/// Adapts fields by selected type and defaults by active tab.
struct CreateSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FolderRecord.createdAt) private var folders: [FolderRecord]

    @Binding var isPresented: Bool
    let defaultType: CreateItemType

    @State private var text = ""
    @State private var selectedType: CreateItemType = .auto
    @State private var selectedFolder: FolderRecord? = nil
    @State private var selectedDate: Date? = nil
    @State private var isShowingDatePicker = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.10)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 10) {
                inputCard
                typePill
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 86)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.snappy(duration: 0.2), value: selectedType)
        .onAppear {
            selectedType = defaultType
            if defaultType == .event {
                selectedDate = Date()
            }
            isFocused = true
        }
        .sheet(isPresented: $isShowingDatePicker) {
            datePickerSheet
                .presentationDetents([.height(420)])
                .presentationDragIndicator(.visible)
                .presentationBackground(AppTheme.backgroundTop)
                .preferredColorScheme(services.appearancePreference.colorScheme)
        }
    }

    private var inputCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if showsFolderPicker {
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
                        HStack(spacing: 6) {
                            Image(systemName: selectedFolder == nil ? "tray" : "folder.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text(selectedFolder?.name ?? "Inbox")
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(AppTheme.surfaceSecondary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if showsDatePicker {
                    Button {
                        if selectedDate == nil { selectedDate = Date().addingTimeInterval(3600) }
                        isShowingDatePicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.system(size: 13, weight: .semibold))
                            if let date = selectedDate {
                                Text(dateLabel(for: date))
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                            } else {
                                Text("Pick date")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(AppTheme.surfaceSecondary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(action: handleCreate) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(AppPrimaryButtonStyle())
                .clipShape(Circle())
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            TextField(placeholderText, text: $text, axis: .vertical)
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.5)
                .lineLimit(1...5)
                .focused($isFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
        }
        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }

    private var typePill: some View {
        HStack(spacing: 0) {
            ForEach(CreateItemType.allCases) { type in
                Button {
                    withAnimation(.snappy(duration: 0.15)) { selectedType = type }
                    if type == .event, selectedDate == nil {
                        selectedDate = Date()
                    }
                } label: {
                    Image(systemName: type.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(selectedType == type ? AppTheme.accentBlue : AppTheme.mutedText)
                        .frame(width: 54, height: 42)
                        .background(
                            selectedType == type ? AppTheme.accentBlue.opacity(0.12) : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(AppTheme.surfacePrimary, in: Capsule())
        .overlay(
            Capsule()
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        )
    }

    private var datePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker(
                    selectedType == .event ? "Event Date" : "Due Date",
                    selection: Binding(
                        get: { selectedDate ?? Date() },
                        set: { selectedDate = $0 }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .padding(.horizontal, 16)

                if selectedDate != nil {
                    Button(role: .destructive) {
                        selectedDate = nil
                        isShowingDatePicker = false
                    } label: {
                        Label("Clear Date", systemImage: "xmark.circle")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(AppTheme.danger)
                    .padding(.top, 12)
                }
            }
            .navigationTitle(selectedType == .event ? "Set Event Date" : "Set Due Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isShowingDatePicker = false }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var placeholderText: String {
        switch selectedType {
        case .auto:  return "Write anything…"
        case .task:  return "New Task"
        case .event: return "New Event"
        case .email: return "New Email"
        }
    }

    private var showsFolderPicker: Bool {
        selectedType == .auto || selectedType == .task
    }

    private var showsDatePicker: Bool {
        selectedType == .auto || selectedType == .task || selectedType == .event
    }

    private func close() {
        withAnimation(.snappy(duration: 0.2)) {
            isPresented = false
        }
    }

    private func createTask(_ input: String) {
        services.captureService.capture(
            rawComposerText: input,
            attachmentNames: [],
            selectedFolder: selectedFolder,
            overrideDueDate: selectedDate,
            in: modelContext
        )
    }

    private func createEvent(_ input: String) async {
        let startDate = selectedDate ?? Date()
        let hasAccess: Bool
        if services.calendarService.canCreateEvents() {
            hasAccess = true
        } else {
            hasAccess = await services.calendarService.requestAccess()
        }

        guard hasAccess else {
            // Fallback to task so the input is never lost if calendar permission is denied.
            createTask(input)
            return
        }

        do {
            try await services.calendarService.createEvent(
                title: input,
                startDate: startDate,
                endDate: startDate.addingTimeInterval(3600)
            )
        } catch {
            createTask(input)
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

    private func handleCreate() {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        let resolvedType = selectedType == .auto ? resolveAutoType(for: input) : selectedType

        Task {
            switch resolvedType {
            case .task:
                createTask(input)
            case .event:
                await createEvent(input)
            case .email:
                services.composeEmailSeedBody = input
                services.showsComposeEmail = true
            case .auto:
                createTask(input)
            }
            close()
        }
    }
}

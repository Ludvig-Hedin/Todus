import SwiftUI

/// Universal create sheet — triggered by the FAB plus button.
/// Lets the user type text and choose what to create: Auto, Task, Event, or Email.
struct CreateSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var selectedType: CreateItemType = .auto
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            // Drag indicator area
            VStack(spacing: 16) {
                // Text input
                TextField("What's up?", text: $text, axis: .vertical)
                    .font(.system(size: 17, weight: .medium))
                    .lineLimit(3...6)
                    .focused($isFocused)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppTheme.surfacePrimary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    )

                // Type selector pills
                HStack(spacing: 8) {
                    ForEach(CreateItemType.allCases) { type in
                        Button {
                            withAnimation(.snappy(duration: 0.15)) {
                                selectedType = type
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: type.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(type.title)
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedType == type
                                          ? AppTheme.accent.opacity(0.15)
                                          : AppTheme.surfacePrimary)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(selectedType == type
                                            ? AppTheme.accent.opacity(0.3)
                                            : AppTheme.cardBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Create button
                Button {
                    handleCreate()
                } label: {
                    Text("Create")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(text.isEmpty ? AppTheme.surfaceSecondary : AppTheme.accent)
                        )
                        .foregroundStyle(text.isEmpty ? Color.secondary : Color.white)
                }
                .buttonStyle(.plain)
                .disabled(text.isEmpty)
            }
            .padding(20)
        }
        .onAppear { isFocused = true }
    }

    private func handleCreate() {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        switch selectedType {
        case .auto:
            // TODO: Send to AI for intent detection, route accordingly
            // For now, default to creating a task
            createTask(input)
        case .task:
            createTask(input)
        case .event:
            // TODO: Parse date/title, create EKEvent via CalendarService
            createTask(input) // Fallback to task for now
        case .email:
            // TODO: Dismiss and present EmailComposeView with text as body seed
            break
        }

        dismiss()
    }

    private func createTask(_ input: String) {
        services.captureService.capture(
            rawComposerText: input,
            attachmentNames: [],
            selectedFolder: nil,
            overrideDueDate: nil,
            in: modelContext
        )
    }
}

import SwiftUI
import SwiftData

/// macOS sheet for creating or editing a folder. Includes color and icon pickers.
struct MacFolderEditSheet: View {
    enum Mode {
        case create
        case edit(FolderRecord)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(MacAppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    var onSaved: ((FolderRecord) -> Void)? = nil

    @State private var name: String = ""
    @State private var selectedColor: String?
    @State private var selectedIcon: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacTheme.textSecondary)
                TextField("Folder name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacTheme.textSecondary)
                HStack(spacing: 10) {
                    ForEach(Self.colorPalette, id: \.self) { hex in
                        let isSelected = selectedColor?.lowercased() == hex.lowercased()
                        Button {
                            selectedColor = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex) ?? MacTheme.textSecondary)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .strokeBorder(MacTheme.textPrimary.opacity(isSelected ? 0.9 : 0), lineWidth: 1.6)
                                        .padding(-2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        selectedColor = nil
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(MacTheme.cardBorder, lineWidth: 1)
                                .frame(width: 22, height: 22)
                            Image(systemName: "slash.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(MacTheme.mutedText)
                        }
                        .overlay(
                            Circle()
                                .strokeBorder(MacTheme.textPrimary.opacity(selectedColor == nil ? 0.9 : 0), lineWidth: 1.6)
                                .padding(-2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Icon")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacTheme.textSecondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                    ForEach(Self.iconPalette, id: \.self) { symbol in
                        let isSelected = selectedIcon == symbol
                        let tint: Color = {
                            if let hex = selectedColor, let c = Color(hex: hex) { return c }
                            return MacTheme.textSecondary
                        }()
                        Button {
                            selectedIcon = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(isSelected ? tint : MacTheme.textSecondary)
                                .frame(width: 30, height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isSelected ? tint.opacity(0.18) : MacTheme.surfaceHover)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(MacTheme.contentBackground)
        .onAppear(perform: hydrate)
    }

    private var title: String {
        switch mode {
        case .create: return "New Folder"
        case .edit: return "Edit Folder"
        }
    }

    private func hydrate() {
        switch mode {
        case .create:
            if selectedColor == nil { selectedColor = Self.colorPalette.first }
            if selectedIcon == nil { selectedIcon = Self.iconPalette.first }
        case .edit(let folder):
            name = folder.name
            selectedColor = folder.colorHex
            selectedIcon = folder.iconName
        }
    }

    private func save() async {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        switch mode {
        case .create:
            if let folder = await services.createSharedFolder(
                name: cleaned,
                colorHex: selectedColor,
                iconName: selectedIcon,
                in: modelContext
            ) {
                onSaved?(folder)
            }
        case .edit(let folder):
            await services.updateSharedFolder(
                folder,
                name: cleaned,
                colorHex: .some(selectedColor),
                iconName: .some(selectedIcon),
                in: modelContext
            )
            onSaved?(folder)
        }
        dismiss()
    }

    static let colorPalette: [String] = [
        "#F87171", "#FB923C", "#F59E0B", "#84CC16", "#22C55E", "#14B8A6",
        "#0EA5E9", "#6366F1", "#A855F7", "#EC4899", "#94A3B8",
    ]

    static let iconPalette: [String] = [
        "folder.fill", "tray.fill", "briefcase.fill", "house.fill",
        "person.2.fill", "graduationcap.fill", "airplane", "cart.fill",
        "creditcard.fill", "heart.fill", "star.fill", "flag.fill",
        "tag.fill", "lightbulb.fill", "book.fill", "calendar",
        "envelope.fill", "checkmark.seal.fill", "music.note", "leaf.fill",
        "globe", "gearshape.fill", "sparkles", "bolt.fill",
    ]
}

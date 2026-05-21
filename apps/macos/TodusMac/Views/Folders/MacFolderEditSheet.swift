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
    @State private var isSaving = false
    // Track which pickers the user actually touched in edit mode so the PATCH
    // only sends fields the user changed. Hydration on `.onAppear` does not
    // flip these — only the picker buttons do.
    @State private var didChangeColor = false
    @State private var didChangeIcon = false

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
                            didChangeColor = true
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
                        didChangeColor = true
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
                            didChangeIcon = true
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
                Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        isSaving
                            || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(MacTheme.contentBackground)
        .focusEffectDisabled()
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
        // Prevent double-submit when the Save button is mashed before the
        // network round-trip completes.
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

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
            // Double-optional: .none ⇒ leave field alone; .some(value) ⇒ overwrite
            // with `value` (which itself may be nil to clear the field).
            let colorArg: String?? = didChangeColor ? .some(selectedColor) : .none
            let iconArg: String?? = didChangeIcon ? .some(selectedIcon) : .none
            await services.updateSharedFolder(
                folder,
                name: cleaned,
                colorHex: colorArg,
                iconName: iconArg,
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

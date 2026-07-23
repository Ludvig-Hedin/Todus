import SwiftUI
import SwiftData

/// Sheet for creating a new folder or editing an existing one.
/// Includes name, color swatch picker, and SF Symbol icon picker.
struct FolderEditSheet: View {
    enum Mode {
        case create
        case edit(FolderRecord)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    var onSaved: ((FolderRecord) -> Void)? = nil

    @State private var name: String = ""
    @State private var selectedColor: String?
    @State private var selectedIcon: String?
    /// Inline error shown when create fails (e.g. a folder with this name
    /// already exists). Previously a failed create still played the success
    /// haptic and dismissed, silently dropping the chosen color/icon.
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Folder name", text: $name)
                        .font(.system(size: 16, weight: .medium))
                        .submitLabel(.done)
                        .onChange(of: name) { _, _ in saveError = nil }
                    if let saveError {
                        Text(saveError)
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.danger)
                    }
                }

                Section("Color") {
                    colorPicker
                }

                Section("Icon") {
                    iconPicker
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.sheetBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear(perform: hydrate)
    }

    private var title: String {
        switch mode {
        case .create: return "New Folder"
        case .edit: return "Edit Folder"
        }
    }

    private var colorPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
            ForEach(Self.colorPalette, id: \.self) { hex in
                let isSelected = selectedColor?.lowercased() == hex.lowercased()
                Button {
                    selectedColor = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(isSelected ? 0.9 : 0), lineWidth: 2)
                                .padding(-3)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.colorName(for: hex))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            // "No color" option
            Button {
                selectedColor = nil
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(AppTheme.strongBorder, lineWidth: 1)
                        .frame(width: 32, height: 32)
                    Image(systemName: "slash.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.mutedText)
                }
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(selectedColor == nil ? 0.9 : 0), lineWidth: 2)
                        .padding(-3)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("No color")
            .accessibilityAddTraits(selectedColor == nil ? .isSelected : [])
        }
        .padding(.vertical, 4)
    }

    private var iconPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            ForEach(Self.iconPalette, id: \.self) { symbol in
                let isSelected = selectedIcon == symbol
                let tint: Color = {
                    if let hex = selectedColor { return Color(hex: hex) }
                    return AppTheme.subtleText
                }()
                Button {
                    selectedIcon = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? tint : AppTheme.subtleText)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? tint.opacity(0.18) : AppTheme.surfaceSecondary)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Self.iconName(for: symbol)) icon")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
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

    private func save() {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let service = services.captureService

        switch mode {
        case .create:
            switch service.createFolderExclusive(
                named: cleaned,
                colorHex: selectedColor,
                iconName: selectedIcon,
                in: modelContext
            ) {
            case .created(let folder):
                onSaved?(folder)
            case .duplicate:
                saveError = "A folder named \"\(cleaned)\" already exists."
                AppHaptic.error.play()
                return
            case .invalidName:
                saveError = "Enter a folder name."
                AppHaptic.error.play()
                return
            case .saveFailed:
                saveError = "The folder could not be saved. Try again."
                AppHaptic.error.play()
                return
            }
        case .edit(let folder):
            if folder.name != cleaned {
                switch service.renameFolder(folder, to: cleaned, in: modelContext) {
                case .renamed:
                    break
                case .duplicate:
                    saveError = "A folder named \"\(cleaned)\" already exists."
                    AppHaptic.error.play()
                    return
                case .invalidName:
                    saveError = "Enter a folder name."
                    AppHaptic.error.play()
                    return
                case .saveFailed:
                    saveError = "The folder name could not be saved. Try again."
                    AppHaptic.error.play()
                    return
                }
            }
            guard service.updateFolderAppearance(
                folder,
                colorHex: .some(selectedColor),
                iconName: .some(selectedIcon),
                in: modelContext
            ) else {
                saveError = "The folder appearance could not be saved. Try again."
                AppHaptic.error.play()
                return
            }
            onSaved?(folder)
        }
        AppHaptic.success.play()
        dismiss()
    }

    /// Human-readable name for a palette hex value, used by VoiceOver.
    static func colorName(for hex: String) -> String {
        switch hex.uppercased() {
        case "#F87171": return "Red"
        case "#FB923C": return "Orange"
        case "#F59E0B": return "Amber"
        case "#84CC16": return "Lime"
        case "#22C55E": return "Green"
        case "#14B8A6": return "Teal"
        case "#0EA5E9": return "Sky blue"
        case "#6366F1": return "Indigo"
        case "#A855F7": return "Violet"
        case "#EC4899": return "Pink"
        case "#94A3B8": return "Slate"
        default: return "Color \(hex)"
        }
    }

    /// Human-readable description of an SF Symbol used in the icon picker.
    static func iconName(for symbol: String) -> String {
        symbol
            .replacingOccurrences(of: ".fill", with: "")
            .replacingOccurrences(of: ".", with: " ")
    }

    // Hand-picked, accessible color palette for folder customization.
    static let colorPalette: [String] = [
        "#F87171", // red
        "#FB923C", // orange
        "#F59E0B", // amber
        "#84CC16", // lime
        "#22C55E", // green
        "#14B8A6", // teal
        "#0EA5E9", // sky
        "#6366F1", // indigo
        "#A855F7", // violet
        "#EC4899", // pink
        "#94A3B8", // slate
    ]

    // Curated SF Symbols suitable for folders.
    static let iconPalette: [String] = [
        "folder.fill",
        "tray.fill",
        "briefcase.fill",
        "house.fill",
        "person.2.fill",
        "graduationcap.fill",
        "airplane",
        "cart.fill",
        "creditcard.fill",
        "heart.fill",
        "star.fill",
        "flag.fill",
        "tag.fill",
        "lightbulb.fill",
        "book.fill",
        "calendar",
        "envelope.fill",
        "checkmark.seal.fill",
        "music.note",
        "leaf.fill",
        "globe",
        "gearshape.fill",
        "sparkles",
        "bolt.fill",
    ]
}

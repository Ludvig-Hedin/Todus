import SwiftUI

// MARK: - Signatures List

/// Sub-page in Settings > Email where the user manages their email signatures.
/// Supports create, select, edit, rename, and delete.
struct SignaturesView: View {
    @Environment(AppServices.self) private var services
    @State private var showsAddSheet = false

    var body: some View {
        List {
            // "None" option — clears the active signature
            Section {
                Button {
                    services.selectedSignatureID = nil
                } label: {
                    HStack {
                        Text("None")
                            .foregroundStyle(.primary)
                        Spacer()
                        if services.selectedSignatureID == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.primary)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .buttonStyle(.plain)
            } footer: {
                Text("No signature will be appended to outgoing emails.")
            }

            // Existing signatures
            if !services.signatures.isEmpty {
                Section("My Signatures") {
                    ForEach(services.signatures) { sig in
                        NavigationLink {
                            SignatureEditorView(signature: sig)
                        } label: {
                            signatureRow(sig)
                        }
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            let sig = services.signatures[idx]
                            // Clear selected if we're deleting the active one
                            if services.selectedSignatureID == sig.id {
                                services.selectedSignatureID = nil
                            }
                        }
                        services.signatures.remove(atOffsets: indexSet)
                    }
                }
            } else {
                // Empty state
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "signature")
                                .font(.system(size: 28))
                                .foregroundStyle(.tertiary)
                            Text("No signatures yet")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("Tap + to create your first signature")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 20)
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.sheetBackground)
        .navigationTitle("Signatures")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        // New signature is a sheet (not pushed) so Cancel + NavigationStack are needed
        .sheet(isPresented: $showsAddSheet) {
            NavigationStack {
                SignatureEditorView(signature: nil)
            }
            .preferredColorScheme(services.appearancePreference.colorScheme)
        }
    }

    @ViewBuilder
    private func signatureRow(_ sig: EmailSignature) -> some View {
        HStack(spacing: 12) {
            // Checkmark placeholder to keep text alignment consistent
            Group {
                if services.selectedSignatureID == sig.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.primary)
                        .fontWeight(.semibold)
                } else {
                    Color.clear
                }
            }
            .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(sig.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                if !sig.body.isEmpty {
                    Text(sig.body)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Signature Editor

/// Create or edit a single email signature.
/// Presented as a sheet for new signatures and as a pushed page for editing.
struct SignatureEditorView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    /// Existing signature to edit. `nil` means creating a new one.
    let signature: EmailSignature?

    @State private var name = ""
    @State private var signatureBody = ""
    @State private var isActive = false
    @State private var showsDeleteConfirmation = false
    @FocusState private var bodyFocused: Bool

    private var isNew: Bool { signature == nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List {
            // Name field
            Section {
                TextField("e.g. Work, Personal", text: $name)
                    .font(.system(size: 15))
            } header: {
                Text("Name")
            } footer: {
                Text("Shown in the signature picker list.")
            }

            // Body TextEditor
            Section {
                TextEditor(text: $signatureBody)
                    .font(.system(size: 15))
                    .frame(minHeight: 130)
                    .focused($bodyFocused)
                    // Remove TextEditor's default internal padding for better list alignment
                    .padding(.horizontal, -4)
            } header: {
                Text("Signature Text")
            } footer: {
                Text("This text will be appended to your outgoing emails.")
            }

            // Active toggle
            Section {
                Toggle(isOn: $isActive) {
                    Label("Use as active signature", systemImage: "checkmark.seal")
                }
                .tint(AppTheme.switchTint)
            } footer: {
                Text("Only one signature can be active at a time.")
            }

            // Delete button — only for existing signatures
            if !isNew {
                Section {
                    Button(role: .destructive) {
                        showsDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Signature", systemImage: "trash")
                            Spacer()
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.sheetBackground)
        .navigationTitle(isNew ? "New Signature" : "Edit Signature")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Cancel — only shown when presented as a sheet (new signature)
            if isNew {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
        .confirmationDialog(
            "Delete this signature?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSignature() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .onAppear { populateFields() }
    }

    private func populateFields() {
        guard let sig = signature else { return }
        name = sig.name
        signatureBody = sig.body
        isActive = services.selectedSignatureID == sig.id
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let existing = signature,
           let idx = services.signatures.firstIndex(where: { $0.id == existing.id }) {
            // Update existing signature
            services.signatures[idx].name = trimmedName
            services.signatures[idx].body = signatureBody
            // Sync active state
            if isActive {
                services.selectedSignatureID = existing.id
            } else if services.selectedSignatureID == existing.id {
                services.selectedSignatureID = nil
            }
        } else {
            // Create new signature
            let newSig = EmailSignature(name: trimmedName, body: signatureBody)
            services.signatures.append(newSig)
            if isActive {
                services.selectedSignatureID = newSig.id
            }
        }

        dismiss()
    }

    private func deleteSignature() {
        guard let sig = signature else { return }
        if services.selectedSignatureID == sig.id {
            services.selectedSignatureID = nil
        }
        services.signatures.removeAll { $0.id == sig.id }
        dismiss()
    }
}

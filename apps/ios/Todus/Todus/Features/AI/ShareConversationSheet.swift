import SwiftUI

// MARK: - ShareConversationSheet

/// Sheet presented from the AI chat toolbar to create a public share link for the conversation.
/// Supports optional password protection and expiry. On success shows a native ShareLink.
struct ShareConversationSheet: View {
    let conversationId: String
    let conversationTitle: String

    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services

    @State private var title: String
    @State private var visibility: Visibility = .public
    @State private var password: String = ""
    @State private var expiresInDays: ExpiresOption = .never

    @State private var createdSlug: String? = nil
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    private var shareService: ShareConversationService { services.shareConversationService }

    init(conversationId: String, conversationTitle: String) {
        self.conversationId = conversationId
        self.conversationTitle = conversationTitle
        _title = State(initialValue: conversationTitle)
    }

    enum Visibility: String, CaseIterable {
        case `public` = "public"
        case protected = "protected"

        var label: String {
            switch self {
            case .public: return "Anyone with the link"
            case .protected: return "Password required"
            }
        }
    }

    enum ExpiresOption: String, CaseIterable, Identifiable {
        case never, day = "1", week = "7", month = "30"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .never: return "Never"
            case .day: return "24 hours"
            case .week: return "7 days"
            case .month: return "30 days"
            }
        }
        /// Value sent to the API — "never" maps to "never" for the server, numeric cases pass through.
        var apiValue: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            if let slug = createdSlug {
                successView(slug: slug)
                    .navigationTitle("Link created")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { dismiss() }
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
            } else {
                formView
                    .navigationTitle("Share conversation")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { dismiss() }
                                .font(.system(size: 15))
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            if isLoading {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Button("Create") { Task { await createLink() } }
                                    .font(.system(size: 15, weight: .semibold))
                            }
                        }
                    }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
        .appSheetBackground()
    }

    // MARK: - Form

    @ViewBuilder
    private var formView: some View {
        Form {
            Section("Title") {
                TextField("Conversation title", text: $title)
            }

            Section("Visibility") {
                ForEach(Visibility.allCases, id: \.rawValue) { option in
                    Button {
                        withAnimation(.snappy(duration: 0.15)) { visibility = option }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option == .public ? "Public" : "Protected")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.primary)
                                Text(option.label)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if visibility == option {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if visibility == .protected {
                Section("Password") {
                    SecureField("Enter password", text: $password)
                        .textContentType(.newPassword)
                }
            }

            Section("Expires") {
                Picker("Expiry", selection: $expiresInDays) {
                    ForEach(ExpiresOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Success state

    @ViewBuilder
    private func successView(slug: String) -> some View {
        let urlString = "https://todus.app/share/\(slug)"
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "link.circle.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.primary)

            VStack(spacing: 8) {
                Text("Share link ready")
                    .font(.system(size: 20, weight: .bold))
                Text(urlString)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            HStack(spacing: 12) {
                // Copy to clipboard
                Button {
                    UIPasteboard.general.string = urlString
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
                }
                .buttonStyle(.plain)

                // Native share sheet
                if let url = URL(string: urlString) {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            Text("Manage your shared links in Settings.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Actions

    @MainActor
    private func createLink() async {
        guard !isLoading else { return }

        // Validate that a password is provided when protected visibility is chosen
        if visibility == .protected && password.isEmpty {
            errorMessage = "Please enter a password for the protected link."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let input = ShareCreateInput(
            conversationId: conversationId,
            title: title.isEmpty ? conversationTitle : title,
            password: visibility == .protected ? password : nil,
            expiresInDays: expiresInDays.apiValue
        )

        do {
            let result = try await shareService.createShare(input)
            createdSlug = result.slug
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

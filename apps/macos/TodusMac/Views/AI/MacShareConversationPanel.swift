import SwiftUI

// MARK: - MacShareConversationPanel

/// macOS popover/sheet for creating a shareable link from an AI conversation.
/// Triggered from the MacAssistantPanel toolbar menu when a conversation is active.
struct MacShareConversationPanel: View {
    let conversationId: String
    let conversationTitle: String

    @Environment(MacAppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var visibility: Visibility = .public
    @State private var password: String = ""
    @State private var expiresInDays: ExpiresOption = .never
    @State private var createdSlug: String? = nil
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var copied = false

    private var shareService: ShareConversationService { services.shareConversationService }

    init(conversationId: String, conversationTitle: String) {
        self.conversationId = conversationId
        self.conversationTitle = conversationTitle
        _title = State(initialValue: conversationTitle)
    }

    enum Visibility: String, CaseIterable {
        case `public`, protected
        var label: String {
            switch self {
            case .public: return "Public — anyone with the link"
            case .protected: return "Password protected"
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
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(createdSlug == nil ? "Share conversation" : "Link created")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.3)

            if let slug = createdSlug {
                successContent(slug: slug)
            } else {
                formContent
            }
        }
        .frame(width: 340)
        .background(MacTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Form

    @ViewBuilder
    private var formContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Title
            VStack(alignment: .leading, spacing: 4) {
                Text("Title")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.3)
                TextField("Conversation title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
            }

            // Visibility
            VStack(alignment: .leading, spacing: 4) {
                Text("Visibility")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.3)
                Picker("", selection: $visibility) {
                    ForEach(Visibility.allCases, id: \.rawValue) { opt in
                        Text(opt.label).tag(opt)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            if visibility == .protected {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Password")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.3)
                    SecureField("Enter password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                }
            }

            // Expiry
            HStack {
                Text("Expires")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $expiresInDays) {
                    ForEach(ExpiresOption.allCases) { opt in
                        Text(opt.label).tag(opt)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 110)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            Button {
                Task { await createLink() }
            } label: {
                HStack {
                    if isLoading { ProgressView().scaleEffect(0.7).frame(width: 14, height: 14) }
                    Text(isLoading ? "Creating…" : "Create link")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
        }
        .padding(16)
    }

    // MARK: - Success

    @ViewBuilder
    private func successContent(slug: String) -> some View {
        let urlString = "https://todus.app/share/\(slug)"
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                TextField("", text: .constant(urlString))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .disabled(true)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(urlString, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundStyle(copied ? .green : .primary)
                }
                .buttonStyle(.plain)
                .help("Copy link")
            }
            Text("Manage shared links in Settings → Sharing.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
    }

    // MARK: - Action

    private func createLink() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let input = ShareCreateInput(
            conversationId: conversationId,
            title: title.isEmpty ? conversationTitle : title,
            password: visibility == .protected ? (password.isEmpty ? nil : password) : nil,
            expiresInDays: expiresInDays.rawValue
        )
        do {
            let result = try await shareService.createShare(input)
            await MainActor.run { createdSlug = result.slug }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
}

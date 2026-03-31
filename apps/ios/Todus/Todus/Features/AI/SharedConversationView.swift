import SwiftUI

// MARK: - SharedConversationView

/// Read-only view showing a shared AI conversation snapshot.
/// Opened via deep link: todus://share?slug=abc123
/// Handles password-protected links with an inline unlock form.
struct SharedConversationView: View {
    let slug: String

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .loading
    @State private var title: String = ""
    @State private var messages: [[String: String]] = []
    @State private var passwordInput: String = ""
    @State private var submittedPassword: String? = nil
    @State private var isUnlocking = false
    @State private var wrongPassword = false

    private var shareService: ShareConversationService { services.shareConversationService }

    enum Phase {
        case loading, passwordRequired, loaded, error(String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundTop.ignoresSafeArea()

                switch phase {
                case .loading:
                    ProgressView()
                        .scaleEffect(1.2)

                case .passwordRequired:
                    passwordGateView

                case .loaded:
                    conversationView

                case .error(let message):
                    errorView(message: message)
                }
            }
            .navigationTitle(title.isEmpty ? "Shared conversation" : title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .font(.system(size: 15))
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Password gate

    private var passwordGateView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.circle.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Password required")
                    .font(.system(size: 20, weight: .bold))
                Text("This conversation is password protected.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                SecureField("Enter password", text: $passwordInput)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 32)
                    .onSubmit { Task { await unlock() } }

                if wrongPassword {
                    Text("Incorrect password. Try again.")
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await unlock() }
                } label: {
                    Group {
                        if isUnlocking {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Unlock")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
                .disabled(isUnlocking || passwordInput.isEmpty)
            }

            Spacer()
        }
    }

    // MARK: - Conversation messages

    private var conversationView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(Array(messages.enumerated()), id: \.offset) { _, msg in
                    SharedMessageBubble(role: msg["role"] ?? "user", content: msg["content"] ?? "")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Error state

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "link.badge.plus")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text("Link not available")
                    .font(.system(size: 20, weight: .bold))
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer()
        }
    }

    // MARK: - Load helpers

    private func load(password: String? = nil) async {
        phase = .loading
        do {
            let response = try await shareService.getShare(slug: slug, password: password)
            if response.passwordRequired == true {
                phase = .passwordRequired
            } else {
                title = response.title ?? ""
                messages = response.messages ?? []
                phase = .loaded
            }
        } catch {
            let msg = (error as NSError).localizedDescription
            phase = .error(msg)
        }
    }

    private func unlock() async {
        isUnlocking = true
        wrongPassword = false
        defer { isUnlocking = false }
        submittedPassword = passwordInput
        do {
            let response = try await shareService.getShare(slug: slug, password: passwordInput)
            if response.passwordRequired == true {
                wrongPassword = true
            } else {
                title = response.title ?? ""
                messages = response.messages ?? []
                phase = .loaded
            }
        } catch {
            wrongPassword = true
        }
    }
}

// MARK: - SharedMessageBubble

private struct SharedMessageBubble: View {
    let role: String
    let content: String

    var isUser: Bool { role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }
            Text(content)
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isUser ? Color.blue : AppTheme.surfacePrimary,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .foregroundStyle(isUser ? .white : .primary)
            if !isUser { Spacer(minLength: 60) }
        }
    }
}

import SwiftUI

// MARK: - MacSharedConversationView
//
// TODO(integration): Present this view as a `.sheet` from MacRootView (or any
// long-lived presenter) by observing `Notification.Name.todusOpenSharedConversation`,
// which is broadcast from `TodusMacApp.dispatchValidatedURL` when the user opens a
// `todus://share?slug=...` deep link. Minimal wiring inside MacRootView:
//
//     @State private var pendingShareSlug: String?
//
//     .onReceive(NotificationCenter.default.publisher(for: .todusOpenSharedConversation)) { note in
//         if let slug = note.object as? String { pendingShareSlug = slug }
//     }
//     .sheet(item: Binding(
//         get: { pendingShareSlug.map { SlugWrapper(slug: $0) } },
//         set: { pendingShareSlug = $0?.slug }
//     )) { wrapper in
//         MacSharedConversationView(slug: wrapper.slug)
//             .frame(minWidth: 560, idealWidth: 640, minHeight: 480, idealHeight: 640)
//     }
//
// MacAppServices intentionally is NOT given a `pendingShareSlug` field (the
// service container is owned by another agent and this change must stay
// additive). Routing via NotificationCenter keeps the contact surface zero.

/// Read-only view showing a shared AI conversation snapshot on macOS.
/// Opened via the `todus://share?slug=...` deep link.
/// Handles password-protected links with an inline unlock form.
struct MacSharedConversationView: View {
    let slug: String

    @Environment(MacAppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .loading
    @State private var title: String = ""
    @State private var messages: [[String: String]] = []
    @State private var passwordInput: String = ""
    @State private var isUnlocking = false
    @State private var wrongPassword = false
    /// Client-side brute-force throttle. Each failed attempt increments this;
    /// at 3 we open a cooldown window during which the unlock button is
    /// disabled. After 10 failures, cooldown doubles each round, capped at 5min.
    @State private var unlockAttempts: Int = 0
    @State private var unlockCooldownUntil: Date? = nil
    /// Forces the countdown UI to re-render every second while we're cooling
    /// down. Lightweight — only ticks while a cooldown is active.
    @State private var cooldownTick: Date = .init()
    @State private var isCloning = false
    @State private var clonedConversationId: String? = nil
    @State private var cloneErrorMessage: String? = nil

    private var shareService: ShareConversationService { services.shareConversationService }

    enum Phase {
        case loading
        case passwordRequired
        case loaded
        case error(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().opacity(0.3)

            Group {
                switch phase {
                case .loading:
                    loadingView
                case .passwordRequired:
                    passwordGateView
                case .loaded:
                    conversationView
                case .error(let message):
                    errorView(message: message)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(MacTheme.contentBackground)
        .task { await load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: MacTheme.spacing12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.isEmpty ? "Shared conversation" : title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                    .lineLimit(1)
                Text("Read-only snapshot")
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.textSecondary)
            }

            Spacer()

            if case .loaded = phase {
                // "Save to my conversations" — uses `sharing.import` (same shape as iOS).
                // If the import fails we surface a small inline error rather than
                // replacing the whole conversation view.
                Button {
                    Task { await cloneIntoMyConversations() }
                } label: {
                    HStack(spacing: 6) {
                        if isCloning {
                            ProgressView()
                                .controlSize(.mini)
                        } else if clonedConversationId != nil {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(clonedConversationId == nil ? "Save to my conversations" : "Saved")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        MacTheme.surfaceCard,
                        in: RoundedRectangle(cornerRadius: MacTheme.pillRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: MacTheme.pillRadius, style: .continuous)
                            .stroke(MacTheme.cardBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isCloning || clonedConversationId != nil)
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, MacTheme.spacing16)
        .padding(.vertical, MacTheme.spacing12)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Spacer()
        }
    }

    // MARK: - Password gate

    private var passwordGateView: some View {
        VStack(spacing: MacTheme.spacing24) {
            Spacer()

            Image(systemName: "lock.circle.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Password required")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Text("This conversation is password protected.")
                    .font(.system(size: 13))
                    .foregroundStyle(MacTheme.textSecondary)
            }

            VStack(spacing: MacTheme.spacing8) {
                SecureField("Enter password", text: $passwordInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                    .onSubmit { Task { await unlock() } }

                if wrongPassword {
                    Text(wrongPasswordCopy)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
                if let until = unlockCooldownUntil, until > cooldownTick {
                    let remaining = max(0, Int(until.timeIntervalSince(cooldownTick).rounded(.up)))
                    Text("Too many attempts. Try again in \(remaining)s.")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }

                Button {
                    Task { await unlock() }
                } label: {
                    Group {
                        if isUnlocking {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text("Unlock")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: 280)
                    .padding(.vertical, 8)
                    .background(
                        MacTheme.surfaceCard,
                        in: RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: MacTheme.buttonRadius, style: .continuous)
                            .stroke(MacTheme.cardBorder, lineWidth: 1)
                    )
                    .foregroundStyle(MacTheme.textPrimary)
                }
                .buttonStyle(.plain)
                .disabled(isUnlocking || passwordInput.isEmpty || isInCooldown)
            }
            // Drive the live countdown text only while a cooldown is active.
            // Replaces the previous always-on Timer.publish (1Hz) that ticked
            // every second while the sheet was open regardless of cooldown
            // state. The Task spins only inside the cooldown window and ends
            // as soon as it elapses or the view leaves the cooldown state.
            .task(id: unlockCooldownUntil) {
                guard let until = unlockCooldownUntil, until > Date() else { return }
                while !Task.isCancelled, Date() < until {
                    cooldownTick = Date()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                // Final tick so the countdown text doesn't stick at 1s.
                cooldownTick = Date()
            }

            Spacer()
        }
        .padding(.horizontal, MacTheme.spacing32)
    }

    // MARK: - Conversation messages

    private var conversationView: some View {
        ScrollView {
            LazyVStack(spacing: MacTheme.spacing12) {
                ForEach(Array(messages.enumerated()), id: \.offset) { _, msg in
                    MacSharedMessageBubble(
                        role: msg["role"] ?? "user",
                        content: msg["content"] ?? ""
                    )
                }

                if let cloneErrorMessage {
                    Text(cloneErrorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .padding(.top, MacTheme.spacing8)
                }
            }
            .padding(.horizontal, MacTheme.spacing16)
            .padding(.vertical, MacTheme.spacing12)
        }
    }

    // MARK: - Error state

    private func errorView(message: String) -> some View {
        VStack(spacing: MacTheme.spacing16) {
            Spacer()
            Image(systemName: "link.badge.plus")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("Link not available")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(MacTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MacTheme.spacing24)
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
            phase = .error((error as NSError).localizedDescription)
        }
    }

    private var isInCooldown: Bool {
        guard let until = unlockCooldownUntil else { return false }
        return until > Date()
    }

    /// Wrong-password copy that surfaces the attempt count before cooldown
    /// kicks in. Once the user is in cooldown the dedicated cooldown banner
    /// takes over so we keep this copy minimal.
    private var wrongPasswordCopy: String {
        if unlockAttempts <= 0 { return "Incorrect password. Try again." }
        // Hide the counter while in cooldown — the cooldown banner already
        // tells the user they've exhausted their attempts.
        if isInCooldown { return "Incorrect password." }
        // Before cooldown (attempts 1-2): show "(N/3)" so the user knows
        // when the throttle is about to kick in.
        let limit = 3
        return "Incorrect password (\(min(unlockAttempts, limit))/\(limit))."
    }

    private func registerFailedAttempt() {
        unlockAttempts += 1
        wrongPassword = true
        // 1st two failures: no cooldown. From 3rd onward: enforce a cooldown
        // that grows after 10 attempts. Cap at 5 minutes.
        guard unlockAttempts >= 3 else { return }
        let extraFailures = max(0, unlockAttempts - 9) // 10th + onward = 1+
        let base: TimeInterval = 10
        var cooldown = base * pow(2, Double(extraFailures))
        cooldown = min(cooldown, 300)
        unlockCooldownUntil = Date().addingTimeInterval(cooldown)
        cooldownTick = Date()
    }

    private func unlock() async {
        // Client-side throttle so a determined attacker can't flood the
        // backend from a single client. Server still enforces its own limit.
        if isInCooldown { return }
        isUnlocking = true
        wrongPassword = false
        defer { isUnlocking = false }
        do {
            let response = try await shareService.getShare(slug: slug, password: passwordInput)
            if response.passwordRequired == true {
                registerFailedAttempt()
            } else {
                title = response.title ?? ""
                messages = response.messages ?? []
                phase = .loaded
                unlockAttempts = 0
                unlockCooldownUntil = nil
            }
        } catch let apiError as APIError {
            switch apiError {
            case .unauthorized:
                registerFailedAttempt()
            case .httpError(let statusCode, _) where statusCode == 401 || statusCode == 403:
                registerFailedAttempt()
            default:
                phase = .error(apiError.localizedDescription)
            }
        } catch let urlError as URLError where urlError.code == .userAuthenticationRequired {
            registerFailedAttempt()
        } catch let nsError as NSError where nsError.code == 401 || nsError.code == 403 {
            registerFailedAttempt()
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    private func cloneIntoMyConversations() async {
        cloneErrorMessage = nil
        isCloning = true
        defer { isCloning = false }
        do {
            // `sharing.import` mirrors iOS — it creates a fresh conversation for the
            // current user and returns the new id. We only persist the id locally so
            // the button can flip to "Saved" — opening the cloned conversation is
            // left to the user (the AI assistant panel surfaces all conversations).
            let response = try await shareService.importShare(
                slug: slug,
                password: passwordInput.isEmpty ? nil : passwordInput
            )
            clonedConversationId = response.newConversationId
        } catch {
            cloneErrorMessage = "Could not save: \((error as NSError).localizedDescription)"
        }
    }
}

// MARK: - MacSharedMessageBubble

private struct MacSharedMessageBubble: View {
    let role: String
    let content: String

    private var isUser: Bool { role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 60) }

            Group {
                if isUser {
                    Text(content)
                        .font(.system(size: 13))
                        .foregroundStyle(MacTheme.textPrimary)
                        .padding(.horizontal, MacTheme.spacing12)
                        .padding(.vertical, MacTheme.spacing8)
                        .background(
                            MacTheme.surfaceCard,
                            in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous)
                        )
                } else {
                    MarkdownView(content: content, fontSize: 13)
                        .padding(.horizontal, MacTheme.spacing12)
                        .padding(.vertical, MacTheme.spacing8)
                        .background(
                            MacTheme.surfaceHover,
                            in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous)
                        )
                        .foregroundStyle(MacTheme.textPrimary)
                }
            }
            .frame(maxWidth: 520, alignment: isUser ? .trailing : .leading)
            .textSelection(.enabled)

            if !isUser { Spacer(minLength: 60) }
        }
    }
}

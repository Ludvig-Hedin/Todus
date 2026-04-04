import SwiftUI

// MARK: - Insert mode

/// How the generated draft should be merged into the compose body (explicit user choice).
enum EmailAIDraftInsertMode: Sendable {
    case replace
    case append
}

// MARK: - EmailAIDraftSheet

/// Compact AI drafting assistant for the email composer.
/// The user describes what the email should say; the AI streams a draft body
/// directly into a preview, which can then be inserted into the compose view.
struct EmailAIDraftSheet: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    /// Current compose context, injected from EmailComposeView
    let to: [String]
    let subject: String
    let currentBody: String

    /// Called when the user applies the draft — `mode` selects replace vs append.
    let onInsert: (String, EmailAIDraftInsertMode) -> Void

    @State private var instruction = ""
    @State private var generatedDraft = ""
    @State private var isStreaming = false
    @State private var errorMessage: String?
    @State private var streamingTask: Task<Void, Never>?
    @FocusState private var instructionFocused: Bool

    // AI gradient matching the rest of the app
    private var aiGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0, green: 0xAA/255.0, blue: 0xF5/255.0), location: 0.087),
                .init(color: Color(red: 0xEF/255.0, green: 0, blue: 0xC2/255.0), location: 0.269),
                .init(color: Color(red: 1, green: 0, blue: 0x38/255.0), location: 0.580),
                .init(color: Color(red: 0xF9/255.0, green: 0x9F/255.0, blue: 0), location: 0.913),
            ],
            startPoint: UnitPoint(x: 0.25, y: 0),
            endPoint: UnitPoint(x: 0.75, y: 1)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundTop.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Context pill — shows what the AI knows about this email
                        contextHeader

                        // Instruction input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What should this email say?")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppTheme.mutedText)

                            TextField(
                                text: $instruction,
                                prompt: Text("e.g. Thank them for the meeting and suggest a follow-up call next week").foregroundColor(.secondary),
                                axis: .vertical
                            ) {
                                EmptyView()
                            }
                            .font(.system(size: 15))
                            .lineLimit(3...6)
                            .focused($instructionFocused)
                            .padding(12)
                            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.cardBorder, lineWidth: 1))
                        }

                        // Generated draft preview
                        if !generatedDraft.isEmpty || isStreaming {
                            draftPreview
                        }

                        // Error state
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.danger)
                                .padding(12)
                                .background(AppTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        streamingTask?.cancel()
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .medium))
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isStreaming {
                        Button("Stop") {
                            streamingTask?.cancel()
                            isStreaming = false
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.danger)
                    } else {
                        Button("Generate") {
                            startStreaming()
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("AI Draft")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { instructionFocused = true }
            .onDisappear {
                streamingTask?.cancel()
                streamingTask = nil
            }
        }
    }

    // MARK: - Context Header

    private var contextHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let toFirst = to.first, !toFirst.isEmpty {
                contextPill(icon: "person", text: "To: \(toFirst)")
            }
            if !subject.isEmpty {
                contextPill(icon: "text.justify.left", text: subject)
            }
            if !currentBody.isEmpty {
                contextPill(icon: "doc.text", text: "Has existing draft")
            }
        }
    }

    private func contextPill(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(aiGradient)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(AppTheme.surfacePrimary, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(AppTheme.cardBorder, lineWidth: 1))
    }

    // MARK: - Draft Preview

    private var draftPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                // Animated AI gradient dot while streaming
                if isStreaming {
                    Circle()
                        .fill(aiGradient)
                        .frame(width: 8, height: 8)
                }
                Text("Draft")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isStreaming ? AnyShapeStyle(aiGradient) : AnyShapeStyle(Color.primary))
                Spacer()
                if !generatedDraft.isEmpty && !isStreaming {
                    HStack(spacing: 8) {
                        Button {
                            onInsert(generatedDraft, .replace)
                            dismiss()
                        } label: {
                            Text("Replace body")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppTheme.backgroundTop)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.primary, in: Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
                        Button {
                            onInsert(generatedDraft, .append)
                            dismiss()
                        } label: {
                            Text("Append")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(AppTheme.surfacePrimary, in: Capsule(style: .continuous))
                                .overlay(Capsule(style: .continuous).stroke(AppTheme.cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            ScrollView {
                Text(generatedDraft.isEmpty && isStreaming ? "…" : generatedDraft)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 260)
            .padding(12)
            .background(AppTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.cardBorder, lineWidth: 1))
        }
    }

    // MARK: - Streaming

    private func startStreaming() {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        generatedDraft = ""
        errorMessage = nil
        isStreaming = true
        instructionFocused = false

        let toLine = to.isEmpty ? "" : "To: \(to.joined(separator: ", "))\n"
        let subjectLine = subject.isEmpty ? "" : "Subject: \(subject)\n"
        let existingBody = currentBody.isEmpty ? "" : "\nExisting draft to improve or replace:\n\(currentBody)\n"

        let systemPrompt = """
        You are a concise email drafting assistant. Write ONLY the email body text — no subject line, \
        no metadata. Use plain prose. Keep it professional and natural.

        Email context:
        \(toLine)\(subjectLine)\(existingBody)
        """

        let model = services.aiChatService.selectedModel
        let config = AppConfiguration.load()
        let backendURL = config.effectiveBackendURL
        let appOriginURL = config.effectiveAppURL
        let token = services.authService.bearerToken

        streamingTask = Task { [systemPrompt, model, backendURL, appOriginURL, token, trimmed] in
            defer { Task { @MainActor in isStreaming = false } }
            await streamDraft(
                systemPrompt: systemPrompt,
                userInstruction: trimmed,
                model: model,
                backendURL: backendURL,
                appOriginURL: appOriginURL,
                token: token
            )
        }
    }

    @MainActor
    private func streamDraft(
        systemPrompt: String,
        userInstruction: String,
        model: String,
        backendURL: URL,
        appOriginURL: URL,
        token: String?
    ) async {
        let url = backendURL.appending(path: "api/ai/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Origin required by Better Auth CSRF middleware — pair with the configured web app URL (dev or prod).
        request.setValue(Self.originHeaderValue(for: appOriginURL), forHTTPHeaderField: "Origin")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let payload = ChatRequest(
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: userInstruction)
            ],
            mentions: [],
            tasks: [],
            model: model
        )

        guard let body = try? JSONEncoder().encode(payload) else {
            errorMessage = "Failed to encode request."
            return
        }
        request.httpBody = body

        do {
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                errorMessage = "Server error. Please try again."
                return
            }

            var tokenBuffer = ""

            for try await line in asyncBytes.lines {
                if Task.isCancelled { break }
                guard line.hasPrefix("data: "), line != "data: [DONE]" else { continue }
                let jsonSlice = line.dropFirst(6)
                guard
                    let data = jsonSlice.data(using: .utf8),
                    let chunk = try? JSONDecoder().decode(DraftSSEChunk.self, from: data),
                    let delta = chunk.choices.first?.delta.content,
                    !delta.isEmpty
                else { continue }

                tokenBuffer += delta
                // Flush buffer on natural punctuation / word boundaries to reduce re-renders
                if tokenBuffer.count >= 10 || delta.contains(where: { ".!?,\n".contains($0) }) {
                    generatedDraft += tokenBuffer
                    tokenBuffer = ""
                }
            }

            // Flush any remaining buffer
            if !tokenBuffer.isEmpty {
                generatedDraft += tokenBuffer
            }
        } catch {
            if !Task.isCancelled {
                errorMessage = "Connection error: \(error.localizedDescription)"
            }
        }
    }

    /// Builds an HTTP Origin value from the web app base URL (scheme + host + port, no path).
    private static func originHeaderValue(for appURL: URL) -> String {
        var components = URLComponents(url: appURL, resolvingAgainstBaseURL: false)
        components?.path = ""
        components?.query = nil
        components?.fragment = nil
        if let s = components?.string, !s.isEmpty { return s }
        let scheme = appURL.scheme ?? "https"
        let host = appURL.host ?? ""
        let port = appURL.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }
}

// MARK: - Private SSE model (scoped to this file)

private struct DraftSSEChunk: Decodable {
    let choices: [DraftSSEChoice]
    struct DraftSSEChoice: Decodable {
        let delta: DraftSSEDelta
        struct DraftSSEDelta: Decodable {
            let content: String?
        }
    }
}

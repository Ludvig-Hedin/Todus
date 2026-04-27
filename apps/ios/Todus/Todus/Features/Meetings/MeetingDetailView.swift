import SwiftUI
import AVKit

/// Meeting detail — video player, AI recap, action items, transcript, Q&A.
struct MeetingDetailView: View {
    @Environment(AppServices.self) private var services

    let meetingId: String

    @State private var meeting: MeetingDetailResponse? = nil
    @State private var isLoading = true
    @State private var isGeneratingSummary = false
    @State private var isSchedulingBot = false
    @State private var actionError: String? = nil

    // Stable AVPlayer — avoids recreating on every body render
    @State private var player: AVPlayer? = nil
    @State private var playerUrl: URL? = nil

    // Q&A
    @State private var qaMessages: [(role: String, content: String)] = []
    @State private var qaInput = ""
    @State private var isAskingQuestion = false

    // Transcript
    @State private var showFullTranscript = false

    private var videoURL: URL? {
        guard let rawURL = meeting?.media?.first(where: { $0.mediaType == "video_mixed" })?.url else {
            return nil
        }
        return URL(string: rawURL)
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let meeting {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection(meeting)

                        // Error
                        if meeting.status == "failed", let error = meeting.errorMessage {
                            errorBanner(error)
                        }

                        // Video — AVPlayer stored in state so it survives re-renders
                        if let url = videoURL {
                            VideoPlayer(player: player)
                                .aspectRatio(16/9, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
                                .onAppear {
                                    if playerUrl != url {
                                        playerUrl = url
                                        player = AVPlayer(url: url)
                                    }
                                }
                                .onChange(of: videoURL) { _, newValue in
                                    guard playerUrl != newValue else { return }
                                    playerUrl = newValue
                                    player = newValue.map(AVPlayer.init(url:))
                                }
                        }

                        // Processing placeholder
                        if meeting.status == "recording" || meeting.status == "processing" {
                            processingView(meeting.status)
                        }

                        // AI Summary
                        summarySection(meeting)

                        // Action items
                        if let items = meeting.actionItems, !items.isEmpty {
                            actionItemsSection(items)
                        }

                        // Transcript
                        if let segments = meeting.transcript, !segments.isEmpty {
                            transcriptSection(segments)
                            qaSection
                        }
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView("Meeting not found", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle(meeting?.title ?? "Meeting")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let meeting, meeting.status == "scheduled", meeting.recallBotId == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await scheduleBot() }
                    } label: {
                        if isSchedulingBot {
                            ButtonInlineProgressView(tint: .primary, side: AppTheme.Metrics.toolbarInlineSpinner)
                        } else {
                            Label("Record Meeting", systemImage: "mic")
                        }
                    }
                    .disabled(isSchedulingBot)
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .task { await loadMeeting(showLoading: true) }
    }

    // MARK: - Sections

    private func headerSection(_ meeting: MeetingDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(statusLabel(meeting.status))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(statusColor(meeting.status))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor(meeting.status).opacity(0.12), in: Capsule())

                Spacer()
            }

            Label(
                meeting.startsAt.formatted(date: .long, time: .shortened),
                systemImage: "clock"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            // "Join" button — shown only when the meeting has a known conferencing URL
            // (Zoom, Google Meet, Teams, Webex). Filtering by provider regex avoids
            // surfacing arbitrary links that happen to be in the `meetUrl` field.
            if let joinURL = Self.conferencingURL(in: meeting.meetUrl) {
                Link(destination: joinURL) {
                    Label("Join meeting", systemImage: "video.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Pulls the first Zoom/Meet/Teams/Webex URL out of a free-text field. Used to gate the
    /// Join button so we don't render it for an empty or malformed `meetUrl`.
    private static func conferencingURL(in text: String) -> URL? {
        guard !text.isEmpty else { return nil }
        // Match the four major providers we currently care about. NSRegularExpression is
        // used over String.range(of:options:.regularExpression) so we get a stable match
        // range across Foundation versions.
        let pattern = #"https?://(?:[^\s]*\.)?(zoom\.us|meet\.google\.com|teams\.microsoft\.com|webex\.com)/[^\s]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        let urlString = nsText.substring(with: match.range)
        return URL(string: urlString)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Recording failed")
                    .font(.subheadline.weight(.medium))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous))
    }

    private func processingView(_ status: String) -> some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(status == "recording" ? "Recording in progress..." : "Processing recording...")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
    }

    private func summarySection(_ meeting: MeetingDetailResponse) -> some View {
        Group {
            if let summary = meeting.aiSummary {
                VStack(alignment: .leading, spacing: 8) {
                    Label("AI Recap", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.purple)

                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
            } else if meeting.transcript != nil && !(meeting.transcript?.isEmpty ?? true) {
                HStack {
                    Label("Generate AI recap", systemImage: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        Task { await generateSummary() }
                    } label: {
                        if isGeneratingSummary {
                            ButtonInlineProgressView()
                        } else {
                            Text("Generate")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .controlSize(.small)
                    .disabled(isGeneratingSummary)
                }
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
            }
        }
    }

    private func actionItemsSection(_ items: [MeetingActionItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Action Items", systemImage: "checklist")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.top, 3)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.task)
                            .font(.subheadline)
                        if let owner = item.owner {
                            Text(owner)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
    }

    private func transcriptSection(_ segments: [MeetingTranscriptSegment]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Transcript", systemImage: "text.quote")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)

                Spacer()

                if segments.count > 15 {
                    Button(showFullTranscript ? "Show less" : "Show all") {
                        withAnimation { showFullTranscript.toggle() }
                    }
                    .font(.caption)
                }
            }

            let displaySegments = showFullTranscript ? segments : Array(segments.prefix(15))
            ForEach(displaySegments) { seg in
                HStack(alignment: .top, spacing: 8) {
                    Text(formatMs(seg.startTime))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 36, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(seg.speakerName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(seg.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.04), in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
    }

    // MARK: - Q&A

    private var qaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ask about this meeting", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.purple)

            if !qaMessages.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(qaMessages.enumerated()), id: \.offset) { _, msg in
                        HStack {
                            if msg.role == "user" { Spacer() }

                            Text(msg.content)
                                .font(.caption)
                                .textSelection(.enabled)
                                .padding(8)
                                .background(
                                    msg.role == "user"
                                        ? Color.accentColor.opacity(0.15)
                                        : Color(.secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: AppTheme.Radius.inline, style: .continuous)
                                )
                                .frame(maxWidth: 260, alignment: msg.role == "user" ? .trailing : .leading)

                            if msg.role == "assistant" { Spacer() }
                        }
                    }

                    if isAskingQuestion {
                        HStack {
                            ButtonInlineProgressView(tint: .secondary, side: AppTheme.Metrics.compactInlineSpinner)
                            Spacer()
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Ask a question...", text: $qaInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
                    .onSubmit { Task { await askQuestion() } }

                Button {
                    Task { await askQuestion() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(qaInput.trimmingCharacters(in: .whitespaces).isEmpty || isAskingQuestion)
            }
        }
        .padding(14)
        .background(Color.purple.opacity(0.04), in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
    }

    // MARK: - Actions

    private func loadMeeting(showLoading: Bool = false) async {
        if showLoading {
            isLoading = true
        }
        meeting = await services.meetingsService.getMeeting(id: meetingId)
        isLoading = false
    }

    private func generateSummary() async {
        isGeneratingSummary = true
        actionError = nil
        let result = await services.meetingsService.generateSummary(meetingId: meetingId)
        if result == nil { actionError = "Failed to generate summary. Please try again." }
        await loadMeeting()
        isGeneratingSummary = false
    }

    private func scheduleBot() async {
        isSchedulingBot = true
        actionError = nil
        let success = await services.meetingsService.scheduleBot(meetingId: meetingId)
        if !success { actionError = "Failed to schedule recording. Please try again." }
        await loadMeeting()
        isSchedulingBot = false
    }

    private func askQuestion() async {
        let q = qaInput.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        qaInput = ""
        qaMessages.append((role: "user", content: q))
        isAskingQuestion = true

        if let answer = await services.meetingsService.askQuestion(meetingId: meetingId, question: q) {
            qaMessages.append((role: "assistant", content: answer))
        } else {
            qaMessages.append((role: "assistant", content: "Sorry, I couldn't answer that."))
        }
        isAskingQuestion = false
    }

    // MARK: - Helpers

    private func formatMs(_ ms: Int) -> String {
        let s = ms / 1000
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "scheduled": "Scheduled"
        case "bot_joining": "Starting"
        case "recording": "Recording"
        case "processing": "Processing"
        case "ready": "Ready"
        case "failed": "Failed"
        case "cancelled": "Cancelled"
        default: status.capitalized
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "scheduled": .primary
        case "bot_joining", "processing": .orange
        case "recording": .red
        case "ready": .green
        case "failed": .red
        case "cancelled": .gray
        default: .secondary
        }
    }
}

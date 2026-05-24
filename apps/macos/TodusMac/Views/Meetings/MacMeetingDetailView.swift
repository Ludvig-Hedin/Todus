import SwiftUI
import AVKit

private struct QAChatMessage: Identifiable {
    let id = UUID()
    let role: String
    let content: String
}

// MARK: - Meeting Detail View

struct MacMeetingDetailView: View {
    @Environment(MacAppServices.self) private var services

    let meetingId: String

    @State private var meeting: MeetingDetailResponse? = nil
    @State private var isLoading = true
    @State private var isGeneratingSummary = false
    @State private var isSchedulingBot = false
    @State private var actionError: String? = nil

    // Stable AVPlayer — recreated only when URL changes, not on every render
    @State private var player: AVPlayer? = nil
    @State private var playerUrl: URL? = nil

    // Q&A state
    @State private var qaMessages: [QAChatMessage] = []
    @State private var qaInput = ""
    @State private var isAskingQuestion = false

    // Transcript expansion
    @State private var isTranscriptExpanded = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let meeting {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection(meeting)

                        // Error banner
                        if meeting.status == "failed", let error = meeting.errorMessage {
                            errorBanner(error)
                        }

                        // Video player
                        if let videoUrl = meeting.media?.first(where: { $0.mediaType == "video_mixed" })?.url,
                           let url = URL(string: videoUrl) {
                            videoPlayer(url: url)
                        }

                        // Processing state
                        if meeting.status == "recording" || meeting.status == "processing" {
                            processingPlaceholder(status: meeting.status)
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

                            // Q&A
                            qaSection
                        }
                    }
                    .padding(24)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("Meeting not found")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(MacTheme.contentBackground)
        .alert("Error", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .task {
            await loadMeeting(showLoading: true)
        }
    }

    // MARK: - Sections

    private static func isMeetingOver(startsAt: Date, endsAt: Date?) -> Bool {
        let end = endsAt ?? startsAt.addingTimeInterval(3600)
        return end < Date()
    }

    private func headerSection(_ meeting: MeetingDetailResponse) -> some View {
        let over = Self.isMeetingOver(startsAt: meeting.startsAt, endsAt: meeting.endsAt)
        let displayStatus = (meeting.status == "scheduled" && over) ? "past" : meeting.status
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(meeting.title)
                    .font(.system(size: 18, weight: .semibold))

                Spacer()

                // Status badge
                Text(statusLabel(displayStatus))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor(displayStatus))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor(displayStatus).opacity(0.1), in: Capsule())

                if meeting.status == "scheduled" && meeting.recallBotId == nil && !over {
                    Button {
                        Task { await scheduleBot() }
                    } label: {
                        HStack(spacing: 4) {
                            if isSchedulingBot {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "mic")
                                    .font(.system(size: 11))
                            }
                            Text("Record Meeting")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .macClickablePointer()
                    .disabled(isSchedulingBot)

                }
            }

            HStack(spacing: 12) {
                Label(
                    meeting.startsAt.formatted(date: .long, time: .shortened),
                    systemImage: "clock"
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }

            // Join button — only for upcoming meetings with a known conferencing URL
            if !over, let joinURL = Self.conferencingURL(in: meeting.meetUrl) {
                Link(destination: joinURL) {
                    HStack(spacing: 6) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 11))
                        Text("Join meeting")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .macClickablePointer()
            }
        }
    }

    private static func conferencingURL(in text: String) -> URL? {
        guard !text.isEmpty else { return nil }
        let pattern = #"https?://(?:[^\s]*\.)?(zoom\.us|meet\.google\.com|teams\.microsoft\.com|webex\.com)/[^\s]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        return URL(string: nsText.substring(with: match.range))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Recording failed")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.8))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))
    }

    private func videoPlayer(url: URL) -> some View {
        VideoPlayer(player: player)
            .aspectRatio(16/9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))
            .task(id: url) {
                if playerUrl != url {
                    playerUrl = url
                    player = AVPlayer(url: url)
                }
            }
    }

    private func processingPlaceholder(status: String) -> some View {
        VStack(spacing: 8) {
            ProgressView()
            Text(status == "recording" ? "Meeting is being recorded..." : "Processing recording...")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("The recap will be available once processing completes.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))
    }

    private func summarySection(_ meeting: MeetingDetailResponse) -> some View {
        Group {
            if let summary = meeting.aiSummary {
                VStack(alignment: .leading, spacing: 8) {
                    Label("AI Recap", systemImage: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous).stroke(Color.primary.opacity(0.06)))
            } else if meeting.transcript != nil && !meeting.transcript!.isEmpty {
                HStack {
                    Label("Generate AI recap from transcript", systemImage: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        Task { await generateSummary() }
                    } label: {
                        HStack(spacing: 4) {
                            if isGeneratingSummary {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11))
                            }
                            Text("Generate")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isGeneratingSummary)
                }
                .padding(14)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous).stroke(Color.primary.opacity(0.06)))
            }
        }
    }

    private func actionItemsSection(_ items: [MeetingActionItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Action Items", systemImage: "checklist")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.task)
                            .font(.system(size: 12))

                        if let owner = item.owner {
                            Text("Owner: \(owner)")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous).stroke(Color.primary.opacity(0.1)))
    }

    private func transcriptSection(_ segments: [MeetingTranscriptSegment]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Transcript", systemImage: "text.quote")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if segments.count > 20 {
                    // Tell the user how many segments are hidden so the
                    // affordance hints at the cost of expanding.
                    Button(isTranscriptExpanded ? "Show less" : "Show all (\(segments.count))") {
                        withAnimation { isTranscriptExpanded.toggle() }
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .macClickablePointer()
                    .foregroundStyle(Color.accentColor)
                }
            }

            let displaySegments = isTranscriptExpanded ? segments : Array(segments.prefix(20))
            ForEach(displaySegments) { seg in
                HStack(alignment: .top, spacing: 10) {
                    Text(formatMs(seg.startTime))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 44, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(seg.speakerName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text(seg.text)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous).stroke(Color.primary.opacity(0.06)))
    }

    // MARK: - Q&A

    private var qaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ask about this meeting", systemImage: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if !qaMessages.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(qaMessages) { msg in
                        qaMessageRow(msg)
                    }

                    qaLoadingRow
                }
                .padding(8)
                .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))
            }

            HStack(spacing: 6) {
                qaInputField

                Button {
                    Task { await askQuestion() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        // Tint follows the actual enabled state so the
                        // button doesn't look "live" when it's actually
                        // disabled (empty input or in-flight question).
                        .foregroundStyle(
                            (qaInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAskingQuestion)
                                ? Color.secondary
                                : Color.accentColor
                        )
                }
                .buttonStyle(.plain)
                .macClickablePointer()
                .disabled(qaInput.trimmingCharacters(in: .whitespaces).isEmpty || isAskingQuestion)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous).stroke(Color.primary.opacity(0.06)))
    }

    private var qaInputField: some View {
        TextField("What were the key decisions?", text: $qaInput)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(8)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            .onSubmit { Task { await askQuestion() } }
    }

    private var qaLoadingRow: some View {
        Group {
            if isAskingQuestion {
                HStack {
                    ProgressView().controlSize(.mini)
                    Spacer()
                }
            }
        }
    }

    private func qaMessageRow(_ msg: QAChatMessage) -> some View {
        HStack {
            if msg.role == "user" { Spacer() }

            Text(msg.content)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    msg.role == "user"
                        ? Color.accentColor.opacity(0.15)
                        : Color.primary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous)
                )
                .frame(maxWidth: 400, alignment: msg.role == "user" ? .trailing : .leading)
                .textSelection(.enabled)

            if msg.role == "assistant" { Spacer() }
        }
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
        qaMessages.append(QAChatMessage(role: "user", content: q))
        isAskingQuestion = true

        if let answer = await services.meetingsService.askQuestion(meetingId: meetingId, question: q) {
            qaMessages.append(QAChatMessage(role: "assistant", content: answer))
        } else {
            qaMessages.append(QAChatMessage(role: "assistant", content: "Sorry, I could not answer that question."))
        }
        isAskingQuestion = false
    }

    // MARK: - Helpers

    private func formatMs(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "scheduled": "Scheduled"
        case "past": "Past"
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
        case "past": .secondary
        case "bot_joining", "processing": .orange
        case "recording": .red
        case "ready": .green
        case "failed": .red
        case "cancelled": .gray
        default: .secondary
        }
    }
}

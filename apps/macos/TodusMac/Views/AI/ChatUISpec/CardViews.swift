import SwiftUI
import AppKit

// MARK: - Shared

/// Container that wraps any view in a rounded outlined card with MacTheme styling.
private struct MacCard<Content: View>: View {
    var radius: CGFloat = MacTheme.rowRadius
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
    }
}

private let kMacGroupedThreshold: Int = 4

private enum MacCardDateFormatting {
    nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
}

private func macFormatDate(_ iso: String) -> String {
    guard let date = MacCardDateFormatting.isoFormatter.date(from: iso)
            ?? ISO8601DateFormatter().date(from: iso) else { return iso }
    return MacCardDateFormatting.displayDateFormatter.string(from: date)
}

private func macFormatTimeRange(_ start: String, _ end: String) -> String {
    guard let s = MacCardDateFormatting.isoFormatter.date(from: start) ?? ISO8601DateFormatter().date(from: start),
          let e = MacCardDateFormatting.isoFormatter.date(from: end) ?? ISO8601DateFormatter().date(from: end) else {
        return "\(start) – \(end)"
    }
    return "\(MacCardDateFormatting.timeFormatter.string(from: s)) – \(MacCardDateFormatting.timeFormatter.string(from: e))"
}

private func macIsDatePast(_ iso: String) -> Bool {
    guard let d = MacCardDateFormatting.isoFormatter.date(from: iso)
            ?? ISO8601DateFormatter().date(from: iso) else { return false }
    return d < Date()
}

// MARK: - Email Card

struct MacEmailCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: MacChatUISpecOnAction?

    private var parsed: EmailCardProps? { EmailCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            Button {
                onAction?("navigate_thread", ["threadId": p.threadId], nil)
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(MacTheme.badgeSurface)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(String(p.sender.prefix(1)).uppercased())
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(MacTheme.textSecondary)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(p.sender)
                                .font(.subheadline)
                                .fontWeight(p.isUnread ? .semibold : .regular)
                                .lineLimit(1)
                            Spacer()
                            Text(macFormatDate(p.receivedAt))
                                .font(.caption2)
                                .foregroundStyle(MacTheme.textSecondary)
                        }
                        HStack {
                            Text(p.subject)
                                .font(.caption)
                                .foregroundStyle(p.isUnread ? MacTheme.textPrimary : MacTheme.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            ForEach(p.labels.prefix(2), id: \.name) { label in
                                Text(label.name)
                                    .font(.system(size: 9, weight: .medium))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(MacTheme.badgeSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                        if !p.snippet.isEmpty {
                            Text(p.snippet)
                                .font(.caption2)
                                .foregroundStyle(MacTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Task Card

struct MacTaskCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: MacChatUISpecOnAction?

    private var parsed: TaskCardProps? { TaskCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            Button {
                onAction?("navigate_task", ["taskId": p.taskId], nil)
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: statusIcon(p.status))
                        .font(.system(size: 14))
                        .foregroundStyle(statusColor(p.status))
                        .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(p.title)
                                .font(.subheadline)
                                .strikethrough(p.status == "done")
                                .foregroundStyle(p.status == "done" ? MacTheme.textSecondary : MacTheme.textPrimary)
                                .lineLimit(2)
                            Spacer()
                            if p.priority != "none" {
                                Text(priorityLabel(p.priority))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(priorityColor(p.priority))
                            }
                        }
                        if let desc = p.description, !desc.isEmpty {
                            Text(desc)
                                .font(.caption2)
                                .foregroundStyle(MacTheme.textSecondary)
                                .lineLimit(1)
                        }
                        HStack(spacing: 4) {
                            if let due = p.dueDate {
                                let isOverdue = p.status != "done" && macIsDatePast(due)
                                Text(isOverdue ? "Overdue · \(macFormatDate(due))" : macFormatDate(due))
                                    .font(.caption2)
                                    .foregroundStyle(isOverdue ? .red : MacTheme.textSecondary)
                            }
                            if let folder = p.folderName {
                                Text(p.dueDate != nil ? "· \(folder)" : folder)
                                    .font(.caption2)
                                    .foregroundStyle(MacTheme.textSecondary)
                            }
                        }
                    }
                }
                .padding(8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func statusIcon(_ s: String) -> String {
        switch s { case "done": "checkmark.circle.fill"; case "doing": "clock.fill"; default: "circle" }
    }
    private func statusColor(_ s: String) -> Color {
        switch s { case "done": .green; case "doing": .orange; default: MacTheme.textSecondary }
    }
    private func priorityLabel(_ p: String) -> String {
        switch p { case "high": "High"; case "medium": "Med"; case "low": "Low"; default: "" }
    }
    private func priorityColor(_ p: String) -> Color {
        switch p { case "high": .red; case "medium": .orange; case "low": MacTheme.textSecondary; default: MacTheme.textSecondary }
    }
}

// MARK: - Calendar Event Card

struct MacCalendarEventCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: MacChatUISpecOnAction?

    private var parsed: CalendarEventCardProps? { CalendarEventCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            Button {
                onAction?("navigate_event", ["eventId": p.eventId], nil)
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(MacTheme.accent)
                        .frame(width: 3, height: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10))
                                .foregroundStyle(MacTheme.textSecondary)
                            Text("\(macFormatDate(p.start)) · \(p.isAllDay ? "All day" : macFormatTimeRange(p.start, p.end))")
                                .font(.caption2)
                                .foregroundStyle(MacTheme.textSecondary)
                        }
                        if let location = p.location, !location.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin")
                                    .font(.system(size: 10))
                                    .foregroundStyle(MacTheme.textSecondary)
                                Text(location).font(.caption2).foregroundStyle(MacTheme.textSecondary).lineLimit(1)
                            }
                        }
                    }
                }
                .padding(8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Note Card

struct MacNoteCardView: View {
    let props: [String: ChatJSONValue]

    private var parsed: NoteCardProps? { NoteCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: p.isPinned ? "pin.fill" : "note.text")
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.textSecondary)
                Text(p.content)
                    .font(.subheadline)
                    .lineLimit(4)
            }
            .padding(10)
            .background(MacTheme.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))
        }
    }
}

// MARK: - Draft Card

struct MacDraftCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: MacChatUISpecOnAction?

    private var parsed: DraftCardProps? { DraftCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            Button {
                onAction?("navigate_draft", ["draftId": p.draftId], nil)
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "envelope.open")
                        .font(.system(size: 12))
                        .foregroundStyle(MacTheme.textSecondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.subject.isEmpty ? "(No subject)" : p.subject)
                            .font(.subheadline).fontWeight(.medium).lineLimit(1)
                        if !p.to.isEmpty {
                            Text("To: \(p.to.prefix(2).map { $0.name ?? $0.email }.joined(separator: ", "))")
                                .font(.caption2).foregroundStyle(MacTheme.textSecondary)
                        }
                        if !p.snippet.isEmpty {
                            Text(p.snippet).font(.caption2).foregroundStyle(MacTheme.textSecondary).lineLimit(1)
                        }
                    }
                }
                .padding(8).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Label Card

struct MacLabelCardView: View {
    let props: [String: ChatJSONValue]
    private var parsed: LabelCardProps? { LabelCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            HStack(spacing: 6) {
                Circle()
                    .fill(p.color.flatMap { Color(hex: $0) } ?? MacTheme.textSecondary)
                    .frame(width: 8, height: 8)
                Text(p.name).font(.caption).fontWeight(.medium)
                if let count = p.count {
                    Text("\(count)").font(.caption2).foregroundStyle(MacTheme.textSecondary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(MacTheme.badgeSurface, in: Capsule())
        }
    }
}

// MARK: - Contact Card

struct MacContactCardView: View {
    let props: [String: ChatJSONValue]
    private var parsed: ContactCardProps? { ContactCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            HStack(spacing: 10) {
                Circle().fill(MacTheme.badgeSurface).frame(width: 32, height: 32).overlay(
                    Text(String(p.name.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MacTheme.textSecondary)
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.subheadline).fontWeight(.medium)
                    Text(p.email).font(.caption2).foregroundStyle(MacTheme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
        }
    }
}

// MARK: - Search Result Card

struct MacSearchResultCardView: View {
    let props: [String: ChatJSONValue]
    private var parsed: SearchResultCardProps? { SearchResultCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            VStack(alignment: .leading, spacing: 2) {
                Text("Search: \(p.query)").font(.caption).fontWeight(.semibold)
                Text("\(p.resultCount) result\(p.resultCount == 1 ? "" : "s")")
                    .font(.caption2).foregroundStyle(MacTheme.textSecondary)
                if let summary = p.summary {
                    Text(summary).font(.caption).padding(.top, 2)
                }
            }
            .padding(8)
        }
    }
}

// MARK: - List Cards

struct MacTaskListCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: MacChatUISpecOnAction?

    private var title: String? { props["title"]?.stringValue }
    private var followUp: String? { props["followUp"]?.stringValue }
    private var threshold: Int { max(1, props["groupedThreshold"]?.intValue ?? kMacGroupedThreshold) }
    private var taskDicts: [[String: ChatJSONValue]] {
        (props["tasks"]?.arrayValue ?? []).compactMap { $0.objectValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.subheadline) }

            if taskDicts.count >= threshold {
                MacCard {
                    ForEach(Array(taskDicts.enumerated()), id: \.offset) { idx, task in
                        if idx > 0 { Divider() }
                        MacTaskCardView(props: task, onAction: onAction)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(taskDicts.enumerated()), id: \.offset) { _, task in
                        MacCard { MacTaskCardView(props: task, onAction: onAction) }
                    }
                }
            }

            if let followUp { Text(followUp).font(.subheadline) }
        }
    }
}

struct MacEmailListCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: MacChatUISpecOnAction?

    private var title: String? { props["title"]?.stringValue }
    private var summary: String? { props["summary"]?.stringValue }
    private var emailDicts: [[String: ChatJSONValue]] {
        (props["emails"]?.arrayValue ?? []).compactMap { $0.objectValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.headline) }

            if emailDicts.isEmpty {
                Text("No emails to show.")
                    .font(.subheadline)
                    .foregroundStyle(MacTheme.textSecondary)
            } else {
                MacCard {
                    ForEach(Array(emailDicts.enumerated()), id: \.offset) { idx, email in
                        if idx > 0 { Divider() }
                        MacEmailCardView(props: email, onAction: onAction)
                    }
                }
            }

            if let summary {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Summary").font(.headline)
                    Text(summary).font(.subheadline)
                }
                .padding(.top, 4)
            }
        }
    }
}

struct MacCalendarEventListCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: MacChatUISpecOnAction?

    private var title: String? { props["title"]?.stringValue }
    private var summary: String? { props["summary"]?.stringValue }
    private var eventDicts: [[String: ChatJSONValue]] {
        (props["events"]?.arrayValue ?? []).compactMap { $0.objectValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.headline) }
            MacCard {
                ForEach(Array(eventDicts.enumerated()), id: \.offset) { idx, event in
                    if idx > 0 { Divider() }
                    MacCalendarEventCardView(props: event, onAction: onAction)
                }
            }
            if let summary { Text(summary).font(.subheadline).padding(.top, 4) }
        }
    }
}

struct MacContactListCardView: View {
    let props: [String: ChatJSONValue]

    private var title: String? { props["title"]?.stringValue }
    private var contactDicts: [[String: ChatJSONValue]] {
        (props["contacts"]?.arrayValue ?? []).compactMap { $0.objectValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.headline) }
            MacCard {
                ForEach(Array(contactDicts.enumerated()), id: \.offset) { idx, contact in
                    if idx > 0 { Divider() }
                    MacContactCardView(props: contact)
                }
            }
        }
    }
}

// MARK: - Copyable Text Card

struct MacCopyableTextCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: MacChatUISpecOnAction?

    @State private var copied = false

    private var parsed: CopyableTextCardProps? { CopyableTextCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            VStack(spacing: 0) {
                HStack {
                    Text(p.label).font(.caption).foregroundStyle(MacTheme.textSecondary)
                    Spacer()
                    Button {
                        let pb = NSPasteboard.general
                        pb.declareTypes([.string], owner: nil)
                        pb.setString(p.content, forType: .string)
                        onAction?("copy_text", ["content": p.content], nil)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 11))
                            Text(copied ? "Copied" : "Copy").font(.caption).fontWeight(.medium)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(MacTheme.surfaceCard)

                ScrollView {
                    Text(p.content)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 280)
            }
            .clipShape(RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Inline Compose Card

private struct MacRecipientPill: View {
    let display: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(MacTheme.badgeSurface)
                .frame(width: 16, height: 16)
                .overlay(
                    Text(String(display.prefix(1)).uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(MacTheme.textSecondary)
                )
            Text(display).font(.caption)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 9))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(MacTheme.badgeSurface)
        .clipShape(Capsule())
    }
}

struct MacInlineComposeCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: MacChatUISpecOnAction?

    private var parsed: InlineComposeCardProps? { InlineComposeCardProps(from: props) }

    @State private var to: [(name: String?, email: String)] = []
    @State private var cc: [(name: String?, email: String)] = []
    @State private var bcc: [(name: String?, email: String)] = []
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var showCcBcc = false
    @State private var recipientInput = ""
    @State private var ccInput = ""
    @State private var bccInput = ""
    @State private var saveStatus = "All changes are saved"
    @State private var sendStatus = "draft"
    @State private var debounceTask: Task<Void, Never>? = nil
    @State private var initialDraftId: String? = nil

    var body: some View {
        if let p = parsed {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.fill").font(.system(size: 10))
                        Text("New email").font(.caption).fontWeight(.medium)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(MacTheme.surfaceCard).clipShape(Capsule())
                    Spacer()
                    Button { showCcBcc.toggle() } label: {
                        Image(systemName: showCcBcc ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12)).foregroundStyle(MacTheme.textSecondary)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.top, 12)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("To:").font(.caption).foregroundStyle(MacTheme.textSecondary)
                        ForEach(to, id: \.email) { r in
                            MacRecipientPill(display: r.name ?? r.email, onRemove: isLocked ? nil : {
                                to.removeAll { $0.email == r.email }; markDirty()
                            })
                        }
                        if !isLocked {
                            TextField("Add email…", text: $recipientInput)
                                .textFieldStyle(.plain)
                                .font(.caption)
                                .onSubmit { addRecipient(target: "to") }
                        }
                    }
                    if showCcBcc {
                        HStack {
                            Text("CC:").font(.caption).foregroundStyle(MacTheme.textSecondary)
                            ForEach(cc, id: \.email) { r in
                                MacRecipientPill(display: r.name ?? r.email, onRemove: isLocked ? nil : {
                                    cc.removeAll { $0.email == r.email }; markDirty()
                                })
                            }
                            if !isLocked {
                                TextField("Add email…", text: $ccInput)
                                    .textFieldStyle(.plain)
                                    .font(.caption)
                                    .onSubmit { addRecipient(target: "cc") }
                            }
                            Spacer()
                        }
                        HStack {
                            Text("BCC:").font(.caption).foregroundStyle(MacTheme.textSecondary)
                            ForEach(bcc, id: \.email) { r in
                                MacRecipientPill(display: r.name ?? r.email, onRemove: isLocked ? nil : {
                                    bcc.removeAll { $0.email == r.email }; markDirty()
                                })
                            }
                            if !isLocked {
                                TextField("Add email…", text: $bccInput)
                                    .textFieldStyle(.plain)
                                    .font(.caption)
                                    .onSubmit { addRecipient(target: "bcc") }
                            }
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.top, 8)

                Divider().padding(.vertical, 8)

                TextField("Subject", text: $subject)
                    .textFieldStyle(.plain)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .disabled(isLocked)
                    .onChange(of: subject) { _, _ in markDirty() }

                Divider().padding(.vertical, 8)

                TextEditor(text: $bodyText)
                    .font(.subheadline)
                    .frame(minHeight: 140)
                    .padding(.horizontal, 8)
                    .scrollContentBackground(.hidden)
                    .disabled(isLocked)
                    .onChange(of: bodyText) { _, _ in markDirty() }

                Divider()

                HStack {
                    Text(footerStatusText).font(.caption).foregroundStyle(MacTheme.textSecondary)
                    Spacer()
                    Button {
                        onAction?("attach_to_draft", ["draftId": p.draftId], nil)
                    } label: {
                        Image(systemName: "paperclip")
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(MacTheme.cardBorder, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(isLocked)

                    Button(action: handleSend) {
                        HStack(spacing: 6) {
                            Image(systemName: sendStatus == "sending" ? "hourglass" : sendStatus == "sent" ? "checkmark" : "arrow.up")
                                .font(.system(size: 11, weight: .semibold))
                            Text(sendStatus == "sent" ? "Sent" : "Send").font(.caption).fontWeight(.semibold)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.blue).foregroundColor(.white).clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isLocked || to.isEmpty)
                }
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
            .onAppear {
                // Seed local state once per draftId — re-emissions for the same draft must NOT clobber edits.
                if initialDraftId != p.draftId {
                    initialDraftId = p.draftId
                    to = p.to; cc = p.cc; bcc = p.bcc
                    subject = p.subject; bodyText = p.body
                    showCcBcc = !p.cc.isEmpty || !p.bcc.isEmpty
                    sendStatus = p.status ?? "draft"
                }
            }
        }
    }

    private var isLocked: Bool { sendStatus == "sending" || sendStatus == "sent" }
    private var footerStatusText: String {
        switch sendStatus {
        case "sent": return "Sent"
        case "sending": return "Sending…"
        case "error": return "Failed to send"
        default: return saveStatus
        }
    }

    private func markDirty() {
        saveStatus = "Saving…"
        debounceTask?.cancel()
        let p = parsed
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }
            guard let p else { return }
            await MainActor.run {
                let payload = encodePayload()
                onAction?("update_draft", ["draftId": p.draftId, "payload": payload]) { success, err in
                    if success {
                        saveStatus = "All changes are saved"
                    } else {
                        saveStatus = err ?? "Couldn’t save"
                    }
                }
            }
        }
    }

    private func addRecipient(target: String) {
        // Each row owns its own input field so typing in CC/BCC doesn't bleed
        // into the To field (and vice versa).
        let raw: String
        switch target {
        case "cc": raw = ccInput
        case "bcc": raw = bccInput
        default: raw = recipientInput
        }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        // Reject empty, missing local part, missing domain, or any whitespace inside the address.
        guard let at = trimmed.firstIndex(of: "@"),
              at != trimmed.startIndex,
              at != trimmed.index(before: trimmed.endIndex),
              !trimmed.contains(" ") else { return }
        let normalized = trimmed.lowercased()
        let r = (name: nil as String?, email: trimmed)
        func appendUnique(_ list: inout [(name: String?, email: String)]) {
            if !list.contains(where: { $0.email.lowercased() == normalized }) { list.append(r) }
        }
        switch target {
        case "to": appendUnique(&to); recipientInput = ""
        case "cc": appendUnique(&cc); ccInput = ""
        case "bcc": appendUnique(&bcc); bccInput = ""
        default: return
        }
        markDirty()
    }

    private func handleSend() {
        guard let p = parsed else { return }
        // Cancel any pending autosave so it doesn't race the send mutation.
        debounceTask?.cancel()
        debounceTask = nil
        sendStatus = "sending"
        let payload = encodePayload()
        onAction?("send_draft", ["draftId": p.draftId, "payload": payload]) { success, _ in
            sendStatus = success ? "sent" : "error"
        }
    }

    private func encodePayload() -> String {
        struct Recipient: Encodable { let name: String?; let email: String }
        struct Payload: Encodable {
            let to: [Recipient]; let cc: [Recipient]; let bcc: [Recipient]
            let subject: String; let body: String
        }
        let pl = Payload(
            to: to.map { Recipient(name: $0.name, email: $0.email) },
            cc: cc.map { Recipient(name: $0.name, email: $0.email) },
            bcc: bcc.map { Recipient(name: $0.name, email: $0.email) },
            subject: subject, body: bodyText
        )
        return (try? String(data: JSONEncoder().encode(pl), encoding: .utf8)) ?? "{}"
    }
}

// MARK: - Suggestions Card

struct MacSuggestionsCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: MacChatUISpecOnAction?

    private var parsed: SuggestionsCardProps? { SuggestionsCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(p.suggestions.enumerated()), id: \.offset) { _, s in
                        Button {
                            onAction?(s.action, s.params, nil)
                        } label: {
                            Text(s.label)
                                .font(.caption).fontWeight(.medium)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .overlay(Capsule().stroke(MacTheme.cardBorder, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Action Confirmation Card

struct MacActionConfirmationCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: MacChatUISpecOnAction?

    private var parsed: ActionConfirmationCardProps? { ActionConfirmationCardProps(from: props) }

    private func iconName(_ name: String?) -> String {
        switch name { case "archive": "archivebox"; case "trash": "trash"; case "mail": "envelope"; default: "checkmark" }
    }

    var body: some View {
        if let p = parsed {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.green.opacity(0.15))
                    Image(systemName: iconName(p.icon))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.green)
                }
                .frame(width: 26, height: 26)
                Text(p.message).font(.subheadline)
                Spacer()
                if let undo = p.undoAction {
                    Button {
                        let payload = (try? String(data: JSONEncoder().encode(p.undoParams), encoding: .utf8)) ?? "{}"
                        onAction?("undo", ["undoAction": undo, "undoParams": payload], nil)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward").font(.system(size: 11))
                            Text("Undo").font(.caption).fontWeight(.medium)
                        }
                        .foregroundStyle(Color.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .clipShape(RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Quote Card

struct MacQuoteCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: MacChatUISpecOnAction?

    private var parsed: QuoteCardProps? { QuoteCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.blue).frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.quote).font(.subheadline).italic()
                    if let label = p.sourceLabel {
                        if let action = p.sourceAction {
                            Button {
                                onAction?(action, p.sourceParams, nil)
                            } label: {
                                Text("— \(label)").font(.caption).foregroundStyle(MacTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("— \(label)").font(.caption).foregroundStyle(MacTheme.textSecondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .clipShape(RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Round 2: Attachment Card

struct MacAttachmentCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: MacChatUISpecOnAction?

    private var parsed: AttachmentCardProps? { AttachmentCardProps(from: props) }

    private func iconName(_ mime: String) -> String {
        if mime.hasPrefix("image/") { return "photo" }
        if mime.hasPrefix("video/") { return "play.rectangle" }
        if mime.hasPrefix("audio/") { return "speaker.wave.2" }
        if mime == "application/pdf" || mime.hasPrefix("text/") { return "doc.text" }
        if mime.contains("zip") || mime.contains("compressed") { return "doc.zipper" }
        return "doc"
    }

    private static func formatBytes(_ bytes: Int) -> String {
        if bytes <= 0 { return "" }
        let units = ["B", "KB", "MB", "GB"]
        var i = 0; var n = Double(bytes)
        while n >= 1024 && i < units.count - 1 { n /= 1024; i += 1 }
        return String(format: n < 10 && i > 0 ? "%.1f %@" : "%.0f %@", n, units[i])
    }

    var body: some View {
        if let p = parsed {
            Button {
                let action = p.downloadAction ?? "open_attachment"
                var params: [String: String] = ["name": p.name, "mimeType": p.mimeType]
                if let url = p.previewUrl { params["previewUrl"] = url }
                for (k, v) in p.downloadParams { params[k] = v }
                onAction?(action, params, nil)
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(MacTheme.surfaceCard)
                        Image(systemName: iconName(p.mimeType)).font(.system(size: 14)).foregroundStyle(MacTheme.textSecondary)
                    }
                    .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.subheadline).fontWeight(.medium).lineLimit(1)
                        let suffix = p.mimeType.split(separator: "/").last.map(String.init) ?? p.mimeType
                        Text("\(Self.formatBytes(p.size)) · \(suffix)").font(.caption2).foregroundStyle(MacTheme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.down.circle").font(.system(size: 14)).foregroundStyle(MacTheme.textSecondary)
                }
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous))
        }
    }
}

// MARK: - Round 2: Code Block Card

struct MacCodeBlockCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: MacChatUISpecOnAction?

    @State private var copied = false

    private var parsed: CodeBlockCardProps? { CodeBlockCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 6) {
                        Text(p.language.isEmpty ? "text" : p.language)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.background)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        if let filename = p.filename {
                            Text(filename).font(.caption2).foregroundStyle(MacTheme.textSecondary)
                        }
                    }
                    Spacer()
                    Button {
                        let pb = NSPasteboard.general
                        pb.declareTypes([.string], owner: nil)
                        pb.setString(p.code, forType: .string)
                        onAction?("copy_text", ["content": p.code], nil)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 11))
                            Text(copied ? "Copied" : "Copy").font(.caption).fontWeight(.medium)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(MacTheme.surfaceCard)

                ScrollView([.horizontal, .vertical]) {
                    Text(p.code)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 320)
            }
            .clipShape(RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Round 2: Checklist Card

struct MacChecklistCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: MacChatUISpecOnAction?

    private var parsed: ChecklistCardProps? { ChecklistCardProps(from: props) }

    @State private var checks: [String: Bool] = [:]
    @State private var initialized = false

    var body: some View {
        if let p = parsed {
            VStack(spacing: 0) {
                HStack {
                    Text(p.title ?? "Checklist").font(.subheadline).fontWeight(.medium)
                    Spacer()
                    Text("\(completedCount(p))/\(p.items.count)")
                        .font(.caption2).foregroundStyle(MacTheme.textSecondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(MacTheme.surfaceCard)

                ForEach(Array(p.items.enumerated()), id: \.element.id) { idx, item in
                    if idx > 0 { Divider() }
                    Button {
                        let next = !(checks[item.id] ?? item.done)
                        checks[item.id] = next
                        onAction?("toggle_checklist_item",
                                  ["id": item.id, "done": next ? "true" : "false"], nil)
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
                                    .frame(width: 16, height: 16)
                                if checks[item.id] ?? item.done {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.blue).frame(width: 16, height: 16)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            let isDone = checks[item.id] ?? item.done
                            Text(item.label).font(.subheadline)
                                .strikethrough(isDone)
                                .foregroundStyle(isDone ? MacTheme.textSecondary : MacTheme.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
            .onAppear {
                guard !initialized else { return }
                for item in p.items { checks[item.id] = item.done }
                initialized = true
            }
        }
    }

    private func completedCount(_ p: ChecklistCardProps) -> Int {
        p.items.reduce(0) { $0 + ((checks[$1.id] ?? $1.done) ? 1 : 0) }
    }
}

// MARK: - Round 2: Document Card

struct MacDocumentCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: MacChatUISpecOnAction?

    private var parsed: DocumentCardProps? { DocumentCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            Button {
                onAction?("navigate_document", ["documentId": p.documentId], nil)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(MacTheme.surfaceCard)
                        Image(systemName: "doc.text").font(.system(size: 12)).foregroundStyle(MacTheme.textSecondary)
                    }
                    .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(p.title).font(.subheadline).fontWeight(.medium).lineLimit(1)
                            Spacer()
                            if let updated = p.updatedAt {
                                Text(macFormatDate(updated)).font(.caption2).foregroundStyle(MacTheme.textSecondary)
                            }
                        }
                        if let snippet = p.snippet, !snippet.isEmpty {
                            Text(snippet).font(.caption2).foregroundStyle(MacTheme.textSecondary).lineLimit(2)
                        }
                        if let workspace = p.workspaceName {
                            Text(workspace).font(.system(size: 9)).foregroundStyle(MacTheme.textSecondary)
                        }
                    }
                }
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous))
        }
    }
}

// MARK: - Round 2: Weekly Agenda Card

struct MacWeeklyAgendaCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: MacChatUISpecOnAction?

    private var parsed: WeeklyAgendaCardProps? { WeeklyAgendaCardProps(from: props) }

    private static let dowFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE"; return f }()
    private static let domFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d"; return f }()

    private func parseDate(_ iso: String) -> Date? {
        ISO8601DateFormatter().date(from: iso) ?? {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            return f.date(from: iso)
        }()
    }

    private func densityColor(_ count: Int) -> Color {
        switch count {
        case 0: return .clear
        case 1...2: return Color.blue.opacity(0.18)
        case 3...5: return Color.blue.opacity(0.40)
        default: return Color.blue
        }
    }

    var body: some View {
        if let p = parsed {
            HStack(spacing: 0) {
                ForEach(Array(p.days.prefix(7).enumerated()), id: \.element.id) { idx, day in
                    let date = parseDate(day.date)
                    let isToday = date.map { Calendar.current.isDateInToday($0) } ?? false
                    let total = day.eventCount + day.taskCount
                    let dow = date.map { Self.dowFormatter.string(from: $0) } ?? ""
                    let dom = date.map { Self.domFormatter.string(from: $0) } ?? ""
                    let label = day.label ?? (isToday ? "Today" : dow)

                    if idx > 0 { Divider().frame(height: 56) }
                    Button {
                        onAction?("navigate_day", ["date": day.date], nil)
                    } label: {
                        VStack(spacing: 4) {
                            Text(label.uppercased())
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(MacTheme.textSecondary)
                            ZStack {
                                if isToday { Circle().fill(Color.blue).frame(width: 24, height: 24) }
                                Text(dom)
                                    .font(.system(size: 13, weight: isToday ? .semibold : .regular))
                                    .foregroundStyle(isToday ? Color.white : MacTheme.textPrimary)
                            }
                            ZStack {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(densityColor(total))
                                    .frame(width: 22, height: 16)
                                Text(total == 0 ? "—" : "\(total)")
                                    .font(.system(size: 9, weight: total > 5 ? .semibold : .regular))
                                    .foregroundStyle(total > 5 ? Color.white : MacTheme.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(MacTheme.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Round 2: Metric Card

struct MacMetricCardView: View {
    let props: [String: ChatJSONValue]

    private var parsed: MetricCardProps? { MetricCardProps(from: props) }

    private func deltaIcon(_ dir: String?) -> String {
        switch dir { case "up": "arrow.up"; case "down": "arrow.down"; default: "minus" }
    }
    private func deltaColor(_ dir: String?) -> Color {
        switch dir { case "up": .green; case "down": .red; default: MacTheme.textSecondary }
    }

    var body: some View {
        if let p = parsed {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.label).font(.caption).foregroundStyle(MacTheme.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(p.value)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if let delta = p.delta {
                        HStack(spacing: 2) {
                            Image(systemName: deltaIcon(p.deltaDirection))
                                .font(.system(size: 9, weight: .semibold))
                            Text(delta).font(.caption).fontWeight(.medium)
                        }
                        .foregroundStyle(deltaColor(p.deltaDirection))
                    }
                }
                if let helpText = p.helpText {
                    Text(helpText).font(.caption2).foregroundStyle(MacTheme.textSecondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.rowRadius, style: .continuous)
                    .stroke(MacTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Color hex extension (mirrors iOS)

private extension Color {
    init(specHex hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}



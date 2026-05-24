import SwiftUI

// MARK: - Email Card

struct EmailCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: ChatUISpecOnAction?

    private var parsed: EmailCardProps? { EmailCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            Button(action: { onAction?("navigate_thread", ["threadId": p.threadId], nil) }) {
                HStack(spacing: 10) {
                    // Sender avatar
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(String(p.sender.prefix(1)).uppercased())
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(p.sender)
                                .font(.subheadline)
                                .fontWeight(p.isUnread ? .semibold : .regular)
                                .lineLimit(1)
                            Spacer()
                            Text(formatDate(p.receivedAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text(p.subject)
                                .font(.caption)
                                .foregroundStyle(p.isUnread ? .primary : .secondary)
                                .lineLimit(1)
                            Spacer()
                            // Labels
                            ForEach(p.labels.prefix(2), id: \.name) { label in
                                Text(label.name)
                                    .font(.system(size: 9, weight: .medium))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color(.systemGray5))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                        if !p.snippet.isEmpty {
                            Text(p.snippet)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
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

struct TaskCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: ChatUISpecOnAction?

    private var parsed: TaskCardProps? { TaskCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            Button(action: { onAction?("navigate_task", ["taskId": p.taskId], nil) }) {
                HStack(alignment: .top, spacing: 8) {
                    // Status icon
                    Image(systemName: statusIcon(p.status))
                        .font(.system(size: 14))
                        .foregroundStyle(statusColor(p.status))
                        .frame(width: 18, height: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(p.title)
                                .font(.subheadline)
                                .strikethrough(p.status == "done")
                                .foregroundStyle(p.status == "done" ? .secondary : .primary)
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
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        HStack(spacing: 4) {
                            if let due = p.dueDate {
                                let isOverdue = p.status != "done" && isDatePast(due)
                                Text(isOverdue ? "Overdue · \(formatDate(due))" : formatDate(due))
                                    .font(.caption2)
                                    .foregroundStyle(isOverdue ? .red : .secondary)
                            }
                            if let folder = p.folderName {
                                Text(p.dueDate != nil ? "· \(folder)" : folder)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
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

    private func statusIcon(_ status: String) -> String {
        switch status {
        case "done": return "checkmark.circle.fill"
        case "doing": return "clock.fill"
        default: return "circle"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "done": return .green
        case "doing": return .orange
        default: return .secondary
        }
    }

    private func priorityLabel(_ priority: String) -> String {
        switch priority {
        case "high": return "High"
        case "medium": return "Med"
        case "low": return "Low"
        default: return ""
        }
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "high": return .red
        case "medium": return .orange
        case "low": return .secondary
        default: return .secondary
        }
    }
}

// MARK: - Calendar Event Card

struct CalendarEventCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: ChatUISpecOnAction?

    private var parsed: CalendarEventCardProps? { CalendarEventCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            Button(action: { onAction?("navigate_event", ["eventId": p.eventId], nil) }) {
                HStack(alignment: .top, spacing: 8) {
                    // Color bar — no fixed height so it spans the full row regardless of content
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.5))
                        .frame(width: 3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text("\(formatDate(p.start)) · \(p.isAllDay ? "All day" : formatTimeRange(p.start, p.end))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if let location = p.location, !location.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(location)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        if !p.attendees.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "person.2")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(p.attendees.prefix(3).map { $0.name ?? $0.email }.joined(separator: ", ")
                                     + (p.attendees.count > 3 ? " +\(p.attendees.count - 3)" : ""))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Note Card

struct NoteCardView: View {
    let props: [String: ChatJSONValue]

    private var parsed: NoteCardProps? { NoteCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            HStack(alignment: .top) {
                Text(p.content)
                    .font(.subheadline)
                    .textSelection(.enabled)
                Spacer()
                if p.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(noteColor(p.color))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func noteColor(_ color: String?) -> Color {
        switch color {
        case "yellow": return Color.yellow.opacity(0.1)
        case "blue": return Color.primary.opacity(0.1)
        case "green": return Color.green.opacity(0.1)
        case "red": return Color.red.opacity(0.1)
        case "purple": return Color.purple.opacity(0.1)
        default: return Color(.systemGray6)
        }
    }
}

// MARK: - Draft Card

struct DraftCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: ChatUISpecOnAction?

    private var parsed: DraftCardProps? { DraftCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            Button(action: { onAction?("navigate_draft", ["draftId": p.draftId], nil) }) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(p.subject.isEmpty ? "(No subject)" : p.subject)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Spacer()
                            if let updated = p.updatedAt {
                                Text(formatDate(updated))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !p.to.isEmpty {
                            Text("To: " + p.to.prefix(2).map { $0.name ?? $0.email }.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if !p.snippet.isEmpty {
                            Text(p.snippet)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
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

// MARK: - Label Card

struct LabelCardView: View {
    let props: [String: ChatJSONValue]

    private var parsed: LabelCardProps? { LabelCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: p.color ?? "#E7E7E7"))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "tag")
                            .font(.system(size: 11))
                            .foregroundStyle(p.color != nil ? .white : .secondary)
                    )
                Text(p.name)
                    .font(.subheadline)
                Spacer()
                if let count = p.count {
                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }
}

// MARK: - Contact Card

struct ContactCardView: View {
    let props: [String: ChatJSONValue]

    private var parsed: ContactCardProps? { ContactCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(p.name.prefix(1)).uppercased())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(p.email)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }
}

// MARK: - Search Result Card

struct SearchResultCardView: View {
    let props: [String: ChatJSONValue]

    private var parsed: SearchResultCardProps? { SearchResultCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("Found \(p.resultCount) result\(p.resultCount != 1 ? "s" : "") for \"\(p.query)\"")
                        .font(.subheadline)
                }
                if let summary = p.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - List Cards

/// Wrapper that draws a rounded outlined container around any view.
private struct ListCardContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
    }
}

private let kGroupedThreshold: Int = 4

struct TaskListCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: ChatUISpecOnAction?

    private var title: String? { props["title"]?.stringValue }
    private var followUp: String? { props["followUp"]?.stringValue }
    private var threshold: Int { max(1, props["groupedThreshold"]?.intValue ?? kGroupedThreshold) }
    private var taskDicts: [[String: ChatJSONValue]] {
        (props["tasks"]?.arrayValue ?? []).compactMap { $0.objectValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.subheadline) }

            if taskDicts.count >= threshold {
                ListCardContainer {
                    ForEach(Array(taskDicts.enumerated()), id: \.offset) { idx, taskProps in
                        if idx > 0 { Divider() }
                        TaskCardView(props: taskProps, onAction: onAction)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(taskDicts.enumerated()), id: \.offset) { _, taskProps in
                        ListCardContainer { TaskCardView(props: taskProps, onAction: onAction) }
                    }
                }
            }

            if let followUp { Text(followUp).font(.subheadline) }
        }
    }
}

struct EmailListCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: ChatUISpecOnAction?

    private var title: String? { props["title"]?.stringValue }
    private var summary: String? { props["summary"]?.stringValue }
    private var emailDicts: [[String: ChatJSONValue]] {
        (props["emails"]?.arrayValue ?? []).compactMap { $0.objectValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.headline)
            }

            if emailDicts.isEmpty {
                Text("No emails to show.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ListCardContainer {
                    ForEach(Array(emailDicts.enumerated()), id: \.offset) { idx, emailProps in
                        if idx > 0 { Divider() }
                        EmailCardView(props: emailProps, onAction: onAction)
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

struct CalendarEventListCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: ChatUISpecOnAction?

    private var title: String? { props["title"]?.stringValue }
    private var summary: String? { props["summary"]?.stringValue }
    private var eventDicts: [[String: ChatJSONValue]] {
        // Deduplicate by eventId when present, otherwise by title + date prefix.
        // Prevents same holiday / all-day event from multiple subscribed calendars
        // showing up multiple times in the list.
        var seen = Set<String>()
        return (props["events"]?.arrayValue ?? []).compactMap { $0.objectValue }.filter { dict in
            let key: String
            if let eid = dict["eventId"]?.stringValue {
                key = eid
            } else {
                let title = dict["title"]?.stringValue ?? ""
                let datePrefix = String((dict["start"]?.stringValue ?? "").prefix(10))
                key = "\(title)|\(datePrefix)"
            }
            return seen.insert(key).inserted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.headline) }

            ListCardContainer {
                ForEach(Array(eventDicts.enumerated()), id: \.offset) { idx, eventProps in
                    if idx > 0 { Divider() }
                    CalendarEventCardView(props: eventProps, onAction: onAction)
                }
            }

            if let summary {
                Text(summary).font(.subheadline).padding(.top, 4)
            }
        }
    }
}

struct ContactListCardView: View {
    let props: [String: ChatJSONValue]

    private var title: String? { props["title"]?.stringValue }
    private var contactDicts: [[String: ChatJSONValue]] {
        (props["contacts"]?.arrayValue ?? []).compactMap { $0.objectValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.headline) }

            ListCardContainer {
                ForEach(Array(contactDicts.enumerated()), id: \.offset) { idx, contactProps in
                    if idx > 0 { Divider() }
                    ContactCardView(props: contactProps)
                }
            }
        }
    }
}

// MARK: - Copyable Text Card

struct CopyableTextCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: ChatUISpecOnAction?

    @State private var copied: Bool = false

    private var parsed: CopyableTextCardProps? { CopyableTextCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            VStack(spacing: 0) {
                HStack {
                    Text(p.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = p.content
                        onAction?("copy_text", ["content": p.content], nil)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11))
                            Text(copied ? "Copied" : "Copy")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.sheetCardFill)

                ScrollView {
                    Text(p.content)
                        .font(.subheadline)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 280)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
        }
    }
}

// MARK: - Inline Compose Card

private struct RecipientPill: View {
    let display: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 16, height: 16)
                .overlay(
                    Text(String(display.prefix(1)).uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                )
            Text(display).font(.caption)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 9))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(AppTheme.sheetCardFill)
        .clipShape(Capsule())
    }
}

struct InlineComposeCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: ChatUISpecOnAction?

    private var parsed: InlineComposeCardProps? { InlineComposeCardProps(from: props) }

    @State private var to: [(name: String?, email: String)] = []
    @State private var cc: [(name: String?, email: String)] = []
    @State private var bcc: [(name: String?, email: String)] = []
    @State private var subject: String = ""
    @State private var body_: String = ""
    @State private var showCcBcc: Bool = false
    @State private var recipientInput: String = ""
    @State private var saveStatus: String = "All changes are saved"
    @State private var sendStatus: String = "draft"
    @State private var debounceTask: Task<Void, Never>? = nil
    @State private var initialDraftId: String? = nil

    var body: some View {
        if let p = parsed {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.fill").font(.system(size: 10))
                        Text("New email").font(.caption).fontWeight(.medium)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.sheetCardFill)
                    .clipShape(Capsule())
                    Spacer()
                    Button { showCcBcc.toggle() } label: {
                        Image(systemName: showCcBcc ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                // Recipients
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("To:").font(.caption).foregroundStyle(.secondary)
                        FlexibleRecipientRow(recipients: to, locked: isLocked) { email in
                            to.removeAll { $0.email == email }
                            markDirty()
                        }
                        if !isLocked {
                            TextField("Add email…", text: $recipientInput)
                                .font(.caption)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .onSubmit { addRecipient(target: "to") }
                        }
                    }
                    if showCcBcc {
                        HStack {
                            Text("CC:").font(.caption).foregroundStyle(.secondary)
                            FlexibleRecipientRow(recipients: cc, locked: isLocked) { email in
                                cc.removeAll { $0.email == email }
                                markDirty()
                            }
                            Spacer()
                        }
                        HStack {
                            Text("BCC:").font(.caption).foregroundStyle(.secondary)
                            FlexibleRecipientRow(recipients: bcc, locked: isLocked) { email in
                                bcc.removeAll { $0.email == email }
                                markDirty()
                            }
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                Divider().padding(.vertical, 8)

                // Subject
                TextField("Subject", text: $subject)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .disabled(isLocked)
                    .onChange(of: subject) { _, _ in markDirty() }

                Divider().padding(.vertical, 8)

                // Body
                TextEditor(text: $body_)
                    .font(.subheadline)
                    .frame(minHeight: 120)
                    .padding(.horizontal, 8)
                    .disabled(isLocked)
                    .onChange(of: body_) { _, _ in markDirty() }

                Divider()

                // Footer
                HStack {
                    Text(footerStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        onAction?("attach_to_draft", ["draftId": p.draftId], nil)
                    } label: {
                        Image(systemName: "paperclip")
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(AppTheme.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isLocked)

                    Button(action: handleSend) {
                        HStack(spacing: 6) {
                            Image(systemName: sendStatus == "sending" ? "hourglass" : sendStatus == "sent" ? "checkmark" : "arrow.up")
                                .font(.system(size: 11, weight: .semibold))
                            Text(sendStatus == "sent" ? "Sent" : "Send")
                                .font(.caption).fontWeight(.semibold)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isLocked || to.isEmpty)
                }
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
            .onAppear {
                // Seed local state from spec ONLY on first appearance for this draftId.
                // Subsequent re-emissions from the AI for the same draft must not clobber edits.
                if initialDraftId != p.draftId {
                    initialDraftId = p.draftId
                    to = p.to
                    cc = p.cc
                    bcc = p.bcc
                    subject = p.subject
                    body_ = p.body
                    showCcBcc = !p.cc.isEmpty || !p.bcc.isEmpty
                    sendStatus = p.status ?? "draft"
                }
            }
            .onDisappear {
                // Drop any pending autosave so the callback can't fire after the view
                // is gone and trigger an update_draft action against a stale context.
                debounceTask?.cancel()
                debounceTask = nil
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
            let payload = encodePayload()
            await MainActor.run {
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
        let trimmed = recipientInput.trimmingCharacters(in: .whitespaces)
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
        case "to": appendUnique(&to)
        case "cc": appendUnique(&cc)
        case "bcc": appendUnique(&bcc)
        default: break
        }
        recipientInput = ""
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
            if success {
                sendStatus = "sent"
            } else {
                sendStatus = "error"
            }
        }
    }

    private func encodePayload() -> String {
        struct Recipient: Encodable { let name: String?; let email: String }
        struct Payload: Encodable {
            let to: [Recipient]
            let cc: [Recipient]
            let bcc: [Recipient]
            let subject: String
            let body: String
        }
        let pl = Payload(
            to: to.map { Recipient(name: $0.name, email: $0.email) },
            cc: cc.map { Recipient(name: $0.name, email: $0.email) },
            bcc: bcc.map { Recipient(name: $0.name, email: $0.email) },
            subject: subject,
            body: body_
        )
        return (try? String(data: JSONEncoder().encode(pl), encoding: .utf8)) ?? "{}"
    }
}

private struct FlexibleRecipientRow: View {
    let recipients: [(name: String?, email: String)]
    let locked: Bool
    let onRemove: (String) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(recipients.enumerated()), id: \.offset) { _, r in
                RecipientPill(display: r.name ?? r.email, onRemove: locked ? nil : { onRemove(r.email) })
            }
        }
    }
}

// MARK: - Suggestions Card

struct SuggestionsCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: ChatUISpecOnAction?

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
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .overlay(Capsule().stroke(AppTheme.cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Action Confirmation Card

struct ActionConfirmationCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: ChatUISpecOnAction?

    private var parsed: ActionConfirmationCardProps? { ActionConfirmationCardProps(from: props) }

    private func iconName(_ name: String?) -> String {
        switch name {
        case "archive": return "archivebox"
        case "trash": return "trash"
        case "mail": return "envelope"
        default: return "checkmark"
        }
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
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
        }
    }
}

// MARK: - Quote Card

struct QuoteCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: ChatUISpecOnAction?

    private var parsed: QuoteCardProps? { QuoteCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.blue)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.quote).font(.subheadline).italic()
                    if let label = p.sourceLabel {
                        if let action = p.sourceAction {
                            Button {
                                onAction?(action, p.sourceParams, nil)
                            } label: {
                                Text("— \(label)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }.buttonStyle(.plain)
                        } else {
                            Text("— \(label)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
        }
    }
}

// MARK: - Round 2: Attachment Card

struct AttachmentCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: ChatUISpecOnAction?

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
        var i = 0
        var n = Double(bytes)
        while n >= 1024 && i < units.count - 1 { n /= 1024; i += 1 }
        return String(format: n < 10 && i > 0 ? "%.1f %@" : "%.0f %@", n, units[i])
    }

    var body: some View {
        if let p = parsed {
            Button {
                let action = p.downloadAction ?? "open_attachment"
                var params: [String: String] = [
                    "name": p.name,
                    "mimeType": p.mimeType,
                ]
                if let url = p.previewUrl { params["previewUrl"] = url }
                for (k, v) in p.downloadParams { params[k] = v }
                onAction?(action, params, nil)
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppTheme.sheetCardFill)
                        Image(systemName: iconName(p.mimeType))
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.subheadline).fontWeight(.medium).lineLimit(1)
                        let suffix = p.mimeType.split(separator: "/").last.map(String.init) ?? p.mimeType
                        Text("\(Self.formatBytes(p.size)) · \(suffix)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
        }
    }
}

// MARK: - Round 2: Code Block Card

struct CodeBlockCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: ChatUISpecOnAction?

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
                            .background(AppTheme.surfacePrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        if let filename = p.filename {
                            Text(filename).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        UIPasteboard.general.string = p.code
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
                .background(AppTheme.sheetCardFill)

                ScrollView([.horizontal, .vertical]) {
                    Text(p.code)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 320)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
        }
    }
}

// MARK: - Round 2: Checklist Card

struct ChecklistCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: ChatUISpecOnAction?

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
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(AppTheme.sheetCardFill)

                ForEach(Array(p.items.enumerated()), id: \.element.id) { idx, item in
                    if idx > 0 { Divider() }
                    Button {
                        let next = !(checks[item.id] ?? item.done)
                        checks[item.id] = next
                        onAction?(
                            "toggle_checklist_item",
                            ["id": item.id, "done": next ? "true" : "false"],
                            nil
                        )
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(AppTheme.cardBorder, lineWidth: 1)
                                    .frame(width: 16, height: 16)
                                if checks[item.id] ?? item.done {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.blue)
                                        .frame(width: 16, height: 16)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            let isDone = checks[item.id] ?? item.done
                            Text(item.label)
                                .font(.subheadline)
                                .strikethrough(isDone)
                                .foregroundStyle(isDone ? .secondary : .primary)
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
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

struct DocumentCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: ChatUISpecOnAction?

    private var parsed: DocumentCardProps? { DocumentCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            Button {
                onAction?("navigate_document", ["documentId": p.documentId], nil)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(AppTheme.sheetCardFill)
                        Image(systemName: "doc.text").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(p.title).font(.subheadline).fontWeight(.medium).lineLimit(1)
                            Spacer()
                            if let updated = p.updatedAt {
                                Text(formatDate(updated)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        if let snippet = p.snippet, !snippet.isEmpty {
                            Text(snippet).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                        if let workspace = p.workspaceName {
                            Text(workspace).font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
        }
    }
}

// MARK: - Round 2: Weekly Agenda Card

struct WeeklyAgendaCardView: View {
    let props: [String: ChatJSONValue]
    var onAction: ChatUISpecOnAction?

    private var parsed: WeeklyAgendaCardProps? { WeeklyAgendaCardProps(from: props) }

    private static let dowFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()
    private static let domFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d"; return f
    }()

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

                    if idx > 0 {
                        Divider().frame(height: 56)
                    }
                    Button {
                        onAction?("navigate_day", ["date": day.date], nil)
                    } label: {
                        VStack(spacing: 4) {
                            Text(label.uppercased())
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                            ZStack {
                                if isToday {
                                    Circle().fill(Color.blue).frame(width: 24, height: 24)
                                }
                                Text(dom)
                                    .font(.system(size: 13, weight: isToday ? .semibold : .regular))
                                    .foregroundStyle(isToday ? Color.white : .primary)
                            }
                            ZStack {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(densityColor(total))
                                    .frame(width: 22, height: 16)
                                Text(total == 0 ? "—" : "\(total)")
                                    .font(.system(size: 9, weight: total > 5 ? .semibold : .regular))
                                    .foregroundStyle(total > 5 ? Color.white : .secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(AppTheme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
        }
    }
}

// MARK: - Round 2: Metric Card

struct MetricCardView: View {
    let props: [String: ChatJSONValue]

    private var parsed: MetricCardProps? { MetricCardProps(from: props) }

    private func deltaIcon(_ dir: String?) -> String {
        switch dir { case "up": "arrow.up"; case "down": "arrow.down"; default: "minus" }
    }
    private func deltaColor(_ dir: String?) -> Color {
        switch dir { case "up": .green; case "down": .red; default: .secondary }
    }

    var body: some View {
        if let p = parsed {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.label).font(.caption).foregroundStyle(.secondary)
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
                    Text(helpText).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
        }
    }
}

// MARK: - Helpers

/// Date formatting utilities for card views.
/// ISO8601DateFormatter is not Sendable under Swift 6 strict concurrency, so we keep
/// a shared formatter behind `nonisolated(unsafe)` for this UI-only formatting path.
private enum CardDateFormatting {
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

/// Formats an ISO 8601 string into a short display date (e.g. "Mar 27")
private func formatDate(_ iso: String) -> String {
    guard let date = CardDateFormatting.isoFormatter.date(from: iso)
            ?? ISO8601DateFormatter().date(from: iso) else {
        return iso
    }
    return CardDateFormatting.displayDateFormatter.string(from: date)
}

/// Formats a time range from two ISO strings (e.g. "10:00 AM – 11:00 AM")
private func formatTimeRange(_ start: String, _ end: String) -> String {
    guard let startDate = CardDateFormatting.isoFormatter.date(from: start) ?? ISO8601DateFormatter().date(from: start),
          let endDate = CardDateFormatting.isoFormatter.date(from: end) ?? ISO8601DateFormatter().date(from: end) else {
        return "\(start) – \(end)"
    }
    return "\(CardDateFormatting.timeFormatter.string(from: startDate)) – \(CardDateFormatting.timeFormatter.string(from: endDate))"
}

/// Checks if an ISO 8601 date string is in the past
private func isDatePast(_ iso: String) -> Bool {
    guard let date = CardDateFormatting.isoFormatter.date(from: iso)
            ?? ISO8601DateFormatter().date(from: iso) else { return false }
    return date < Date()
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}


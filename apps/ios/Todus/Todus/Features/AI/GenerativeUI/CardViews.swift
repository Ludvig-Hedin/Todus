import SwiftUI

// MARK: - Email Card

struct EmailCardView: View {
    let props: [String: JSONValue]
    var onAction: ((String, [String: String]) -> Void)?

    private var parsed: EmailCardProps? { EmailCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            Button(action: { onAction?("navigate_thread", ["threadId": p.threadId]) }) {
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
    let props: [String: JSONValue]
    var onAction: ((String, [String: String]) -> Void)?

    private var parsed: TaskCardProps? { TaskCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            Button(action: { onAction?("navigate_task", ["taskId": p.taskId]) }) {
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
        case "low": return .blue
        default: return .secondary
        }
    }
}

// MARK: - Calendar Event Card

struct CalendarEventCardView: View {
    let props: [String: JSONValue]
    var onAction: ((String, [String: String]) -> Void)?

    private var parsed: CalendarEventCardProps? { CalendarEventCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            Button(action: { onAction?("navigate_event", ["eventId": p.eventId]) }) {
                HStack(alignment: .top, spacing: 8) {
                    // Color bar
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue)
                        .frame(width: 3, height: 36)

                    VStack(alignment: .leading, spacing: 3) {
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
                .padding(8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Note Card

struct NoteCardView: View {
    let props: [String: JSONValue]

    private var parsed: NoteCardProps? { NoteCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            HStack(alignment: .top) {
                Text(p.content)
                    .font(.subheadline)
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
        case "blue": return Color.blue.opacity(0.1)
        case "green": return Color.green.opacity(0.1)
        case "red": return Color.red.opacity(0.1)
        case "purple": return Color.purple.opacity(0.1)
        default: return Color(.systemGray6)
        }
    }
}

// MARK: - Draft Card

struct DraftCardView: View {
    let props: [String: JSONValue]
    var onAction: ((String, [String: String]) -> Void)?

    private var parsed: DraftCardProps? { DraftCardProps(from: props) }

    var body: some View {
        if let p = parsed {
            Button(action: { onAction?("navigate_draft", ["draftId": p.draftId]) }) {
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
    let props: [String: JSONValue]

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
    let props: [String: JSONValue]

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
    let props: [String: JSONValue]

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
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Helpers

/// Thread-safe date formatting utilities for card views.
/// Uses nonisolated(unsafe) because DateFormatter is not Sendable,
/// but these are only accessed from the @MainActor UI thread.
private enum CardDateFormatting {
    nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    nonisolated(unsafe) static let timeFormatter: DateFormatter = {
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

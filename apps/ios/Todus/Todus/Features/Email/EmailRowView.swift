import SwiftUI

/// A single email thread row — avatar, sender, subject, snippet, time, unread indicator.
struct EmailRowView: View {
    let thread: EmailThread

    /// Pre-computed once per row instance (rather than on every body re-render). The thread
    /// date doesn't change while the row is visible, so caching is safe and avoids running
    /// Calendar / DateFormatter work for every sibling re-render during scroll or search.
    private let timeString: String

    init(thread: EmailThread) {
        self.thread = thread
        self.timeString = Self.formattedTime(for: thread.date)
    }

    private static func formattedTime(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.dateComponents([.day], from: date, to: Date()).day ?? 0 < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        } else {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Avatar
            SenderAvatarView(email: thread.from.email, name: thread.from.name)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(thread.from.name)
                        .font(.system(size: 15, weight: thread.unread ? .bold : .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(timeString)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.subtleText)
                }

                // Subject + unread indicator on the right
                HStack(spacing: 6) {
                    Text(thread.subject)
                        .font(.system(size: 14, weight: thread.unread ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if thread.unread {
                        Circle()
                            .fill(AppTheme.accentBlue)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(thread.snippet)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.subtleText)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(thread.unread ? "Unread, " : "")From \(thread.from.name), \(thread.subject), \(timeString)")
    }
}

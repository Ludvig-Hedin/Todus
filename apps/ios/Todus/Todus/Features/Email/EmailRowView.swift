import SwiftUI

/// A single email thread row — avatar, sender, subject, snippet, time, unread indicator.
struct EmailRowView: View {
    let thread: EmailThread

    private var timeString: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(thread.date) {
            return thread.date.formatted(date: .omitted, time: .shortened)
        } else if calendar.isDateInYesterday(thread.date) {
            return "Yesterday"
        } else if calendar.dateComponents([.day], from: thread.date, to: Date()).day ?? 0 < 7 {
            return thread.date.formatted(.dateTime.weekday(.abbreviated))
        } else {
            return thread.date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Unread accent bar — uses theme accent for visual consistency
            RoundedRectangle(cornerRadius: 2)
                .fill(thread.unread ? AppTheme.accentBlue : Color.clear)
                .frame(width: 3, height: 40)

            // Avatar
            SenderAvatarView(email: thread.from.email, name: thread.from.name)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(thread.from.name)
                        .font(.system(size: 15, weight: thread.unread ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(timeString)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.mutedText)
                }

                Text(thread.subject)
                    .font(.system(size: 14, weight: thread.unread ? .semibold : .regular))
                    .foregroundStyle(thread.unread ? .primary : AppTheme.subtleText)
                    .lineLimit(1)

                Text(thread.snippet)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 11)
        .padding(.trailing, 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(thread.unread ? "Unread, " : "")From \(thread.from.name), \(thread.subject), \(timeString)")
    }
}

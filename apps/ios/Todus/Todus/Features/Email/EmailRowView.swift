import SwiftUI

/// A single email thread row — sender avatar, subject, snippet, time, unread indicator.
/// Designed for swipe actions in EmailInboxView.
struct EmailRowView: View {
    let thread: EmailThread

    /// Colored initials avatar background based on sender name hash
    private var avatarColor: Color {
        let colors: [Color] = [
            .blue, .purple, .orange, .pink, .teal, .indigo, .mint, .cyan, .brown, .green
        ]
        let hash = abs(thread.from.name.hashValue)
        return colors[hash % colors.count]
    }

    private var initials: String {
        let parts = thread.from.name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(thread.from.name.prefix(2)).uppercased()
    }

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
            // Avatar
            Text(initials)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(avatarColor, in: Circle())

            // Content
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(thread.from.name)
                        .font(.system(size: 15, weight: thread.unread ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text(timeString)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppTheme.mutedText)
                }

                Text(thread.subject)
                    .font(.system(size: 14, weight: thread.unread ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(thread.snippet)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppTheme.subtleText)
                    .lineLimit(1)
            }

            // Unread dot
            if thread.unread {
                Circle()
                    .fill(.blue)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }
}

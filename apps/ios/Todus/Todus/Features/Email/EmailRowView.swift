import SwiftUI

/// A single email thread row — avatar, sender, subject, snippet, time, unread indicator.
struct EmailRowView: View {
    let thread: EmailThread

    /// Computed per render rather than cached in `init`. A cached value captured at row
    /// construction time goes stale across midnight (a "Today" 23:55 message becomes
    /// "Yesterday" but the cached string keeps showing the original time). Recomputing
    /// is cheap — Calendar + DateFormatter calls happen only once per visible row.
    private var timeString: String { Self.formattedTime(for: thread.date) }

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
                            .fill(Color(UIColor.systemBlue))   // was: AppTheme.accentBlue (= Color.primary = black)
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
        // Fall back to the sender's email when the display name is missing —
        // otherwise VoiceOver users hear "From, <subject>" with no sender at all.
        .accessibilityLabel("\(thread.unread ? "Unread, " : "")From \(thread.from.name.isEmpty ? thread.from.email : thread.from.name), \(thread.subject), \(timeString)")
        // Long-press copy actions so users can grab the full sender or subject
        // when either is truncated by the single-line row layout. The wrapping
        // .contextMenu modifier on the row in EmailInboxView (which adds the
        // "Add to folder…" action) is intentionally separate from this one —
        // SwiftUI only honors the innermost .contextMenu, so the parent menu
        // already overrides any inner Text we add. Surface the full strings as
        // copy-to-clipboard buttons instead, which both reveals the full text
        // (label is the value, not truncated by the row) and gives a useful
        // action.
        .contextMenu {
            let senderDisplay = thread.from.name.isEmpty ? thread.from.email : thread.from.name
            Button {
                UIPasteboard.general.string = senderDisplay
            } label: {
                Label("Copy sender: \(senderDisplay)", systemImage: "person")
            }
            if senderDisplay != thread.from.email {
                Button {
                    UIPasteboard.general.string = thread.from.email
                } label: {
                    Label("Copy email address", systemImage: "envelope")
                }
            }
            Button {
                UIPasteboard.general.string = thread.subject
            } label: {
                Label("Copy subject: \(thread.subject)", systemImage: "text.quote")
            }
            if !thread.snippet.isEmpty {
                Button {
                    UIPasteboard.general.string = thread.snippet
                } label: {
                    Label("Copy preview", systemImage: "doc.on.doc")
                }
            }
        }
    }
}

import WidgetKit
import SwiftUI

struct EmailWidget: Widget {
    let kind: String = "EmailWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EmailTimelineProvider()) { entry in
            EmailWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Important Emails")
        .description("Glance at your most important unread emails.")
        #if os(macOS)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        #else
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
        #endif
    }
}

struct EmailWidgetEntryView: View {
    var entry: EmailTimelineProvider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallEmailView(snapshot: entry.snapshot)
        case .systemMedium:
            MediumEmailView(snapshot: entry.snapshot)
        case .systemLarge:
            LargeEmailView(snapshot: entry.snapshot)
        #if !os(macOS)
        case .accessoryRectangular:
            AccessoryEmailView(snapshot: entry.snapshot)
        #endif
        default:
            MediumEmailView(snapshot: entry.snapshot)
        }
    }
}

struct SmallEmailView: View {
    let snapshot: EmailWidgetSnapshot?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "tray.fill")
                    .foregroundColor(.blue)
                Text("Inbox")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.blue)
            }
            
            if let count = snapshot?.unreadImportantCount, count > 0 {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(count)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Important")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.seal")
                            .font(.title2)
                            .foregroundColor(.green)
                        Text("Zero")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .containerBackground(for: .widget) {
            #if os(macOS)
            Color(NSColor.windowBackgroundColor)
            #else
            Color(UIColor.systemBackground)
            #endif
        }
        .widgetURL(URL(string: "todus://email/inbox"))
    }
}

struct MediumEmailView: View {
    let snapshot: EmailWidgetSnapshot?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "tray.fill")
                    .foregroundColor(.blue)
                Text("Important Emails")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.blue)
                Spacer()
                if let count = snapshot?.unreadImportantCount, count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }
            }
            
            if let emails = snapshot?.topEmails, !emails.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(emails.prefix(2)) { email in
                        EmailRow(email: email)
                        if email.id != emails.prefix(2).last?.id {
                            Divider()
                        }
                    }
                }
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.seal")
                            .font(.title)
                            .foregroundColor(.green)
                        Text("Inbox Zero")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
        }
        .padding()
        .containerBackground(for: .widget) {
            #if os(macOS)
            Color(NSColor.windowBackgroundColor)
            #else
            Color(UIColor.systemBackground)
            #endif
        }
        .widgetURL(URL(string: "todus://email/inbox"))
    }
}

struct LargeEmailView: View {
    let snapshot: EmailWidgetSnapshot?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "tray.fill")
                    .foregroundColor(.blue)
                Text("Important Emails")
                    .font(.headline)
                Spacer()
                if let count = snapshot?.unreadImportantCount, count > 0 {
                    Text("\(count) unread")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }
            }
            .padding(.bottom, 4)
            
            if let emails = snapshot?.topEmails, !emails.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(emails.prefix(5)) { email in
                        EmailRow(email: email)
                        if email.id != emails.prefix(5).last?.id {
                            Divider()
                        }
                    }
                }
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                        Text("Inbox Zero")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
        }
        .padding()
        .containerBackground(for: .widget) {
            #if os(macOS)
            Color(NSColor.windowBackgroundColor)
            #else
            Color(UIColor.systemBackground)
            #endif
        }
        .widgetURL(URL(string: "todus://email/inbox"))
    }
}

struct AccessoryEmailView: View {
    let snapshot: EmailWidgetSnapshot?
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                Image(systemName: "tray.fill")
                if let count = snapshot?.unreadImportantCount, count > 0 {
                    Text("\(count) Important")
                        .font(.headline)
                } else {
                    Text("Inbox Zero")
                        .font(.headline)
                }
            }
        }
        .widgetURL(URL(string: "todus://email/inbox"))
    }
}

struct EmailRow: View {
    let email: EmailWidgetSnapshot.EmailInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(email.senderName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .privacySensitive()
            Text(email.subject)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .privacySensitive()
        }
    }
}

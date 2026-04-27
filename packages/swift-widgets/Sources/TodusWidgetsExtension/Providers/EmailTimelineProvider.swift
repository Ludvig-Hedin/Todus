import WidgetKit
import SwiftUI

struct EmailWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: EmailWidgetSnapshot?
}

struct EmailTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> EmailWidgetEntry {
        EmailWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (EmailWidgetEntry) -> Void) {
        if context.isPreview {
            completion(EmailWidgetEntry(date: Date(), snapshot: .placeholder))
            return
        }
        let store = WidgetSnapshotStore.shared.readSnapshot()
        let entry = EmailWidgetEntry(date: Date(), snapshot: store?.email ?? .placeholder)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EmailWidgetEntry>) -> Void) {
        let store = WidgetSnapshotStore.shared.readSnapshot()
        let snapshot = store?.email
        
        let currentDate = Date()
        let entry = EmailWidgetEntry(date: currentDate, snapshot: snapshot)
        
        // Refresh every hour
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate) ?? currentDate.addingTimeInterval(3600)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

extension EmailWidgetSnapshot {
    static var placeholder: EmailWidgetSnapshot {
        EmailWidgetSnapshot(
            unreadImportantCount: 2,
            topEmails: [
                EmailInfo(id: "1", senderName: "Alice", subject: "Project Update"),
                EmailInfo(id: "2", senderName: "Bob", subject: "Lunch today?"),
                EmailInfo(id: "3", senderName: "GitHub", subject: "Merged PR #42")
            ]
        )
    }
}

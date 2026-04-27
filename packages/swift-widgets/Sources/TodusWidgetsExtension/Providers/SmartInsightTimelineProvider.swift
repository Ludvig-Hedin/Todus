import WidgetKit
import SwiftUI

struct SmartInsightWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: SmartInsightWidgetSnapshot?
}

struct SmartInsightTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SmartInsightWidgetEntry {
        SmartInsightWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SmartInsightWidgetEntry) -> Void) {
        if context.isPreview {
            completion(SmartInsightWidgetEntry(date: Date(), snapshot: .placeholder))
            return
        }
        let store = WidgetSnapshotStore.shared.readSnapshot()
        let entry = SmartInsightWidgetEntry(date: Date(), snapshot: store?.insight ?? .placeholder)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SmartInsightWidgetEntry>) -> Void) {
        let store = WidgetSnapshotStore.shared.readSnapshot()
        let snapshot = store?.insight
        
        let currentDate = Date()
        let entry = SmartInsightWidgetEntry(date: currentDate, snapshot: snapshot)
        
        // Insights update hourly
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate) ?? currentDate.addingTimeInterval(3600)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

extension SmartInsightWidgetSnapshot {
    static var placeholder: SmartInsightWidgetSnapshot {
        SmartInsightWidgetSnapshot(
            insightText: "You have 2 meetings before lunch and 3 overdue tasks.",
            recommendedActionText: "Focus on PR review first."
        )
    }
}

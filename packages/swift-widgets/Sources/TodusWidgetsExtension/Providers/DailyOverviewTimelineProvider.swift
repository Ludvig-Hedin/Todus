import WidgetKit
import SwiftUI

struct DailyOverviewWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: DailyOverviewWidgetSnapshot?
}

struct DailyOverviewTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyOverviewWidgetEntry {
        DailyOverviewWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyOverviewWidgetEntry) -> Void) {
        if context.isPreview {
            completion(DailyOverviewWidgetEntry(date: Date(), snapshot: .placeholder))
            return
        }
        let store = WidgetSnapshotStore.shared.readSnapshot()
        let entry = DailyOverviewWidgetEntry(date: Date(), snapshot: store?.overview ?? .placeholder)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyOverviewWidgetEntry>) -> Void) {
        let store = WidgetSnapshotStore.shared.readSnapshot()
        let snapshot = store?.overview
        
        let currentDate = Date()
        let entry = DailyOverviewWidgetEntry(date: currentDate, snapshot: snapshot)
        
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate) ?? currentDate.addingTimeInterval(3600)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

extension DailyOverviewWidgetSnapshot {
    static var placeholder: DailyOverviewWidgetSnapshot {
        DailyOverviewWidgetSnapshot(
            nextEvent: CalendarWidgetSnapshot.Event(id: "1", title: "Product Sync", startDate: Date().addingTimeInterval(3600), endDate: Date().addingTimeInterval(7200), isAllDay: false, colorHex: 0x5B8DEF, url: nil),
            urgentTaskCount: 3,
            unreadImportantEmailCount: 2
        )
    }
}

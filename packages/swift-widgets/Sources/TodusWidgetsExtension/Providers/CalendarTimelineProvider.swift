import WidgetKit
import SwiftUI

struct CalendarWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: CalendarWidgetSnapshot?
}

struct CalendarTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarWidgetEntry {
        CalendarWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (CalendarWidgetEntry) -> Void) {
        if context.isPreview {
            completion(CalendarWidgetEntry(date: Date(), snapshot: .placeholder))
            return
        }
        let store = WidgetSnapshotStore.shared.readSnapshot()
        let entry = CalendarWidgetEntry(date: Date(), snapshot: store?.calendar ?? .placeholder)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarWidgetEntry>) -> Void) {
        let store = WidgetSnapshotStore.shared.readSnapshot()
        let snapshot = store?.calendar
        
        var entries: [CalendarWidgetEntry] = []
        let currentDate = Date()
        entries.append(CalendarWidgetEntry(date: currentDate, snapshot: snapshot))
        
        // Add future entries when events start/end to keep timeline accurate
        if let events = snapshot?.upcomingEvents {
            for event in events {
                if event.startDate > currentDate {
                    entries.append(CalendarWidgetEntry(date: event.startDate, snapshot: snapshot))
                }
                if event.endDate > currentDate {
                    entries.append(CalendarWidgetEntry(date: event.endDate, snapshot: snapshot))
                }
            }
        }
        
        // Refresh every hour at least
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate) ?? currentDate.addingTimeInterval(3600)
        let timeline = Timeline(entries: entries.sorted(by: { $0.date < $1.date }), policy: .after(nextUpdate))
        completion(timeline)
    }
}

extension CalendarWidgetSnapshot {
    static var placeholder: CalendarWidgetSnapshot {
        CalendarWidgetSnapshot(upcomingEvents: [
            Event(id: "1", title: "Team Sync", startDate: Date().addingTimeInterval(3600), endDate: Date().addingTimeInterval(7200), isAllDay: false, colorHex: 0x5B8DEF, url: nil),
            Event(id: "2", title: "Lunch", startDate: Date().addingTimeInterval(7200), endDate: Date().addingTimeInterval(10800), isAllDay: false, colorHex: 0xEF5B5B, url: nil)
        ])
    }
}

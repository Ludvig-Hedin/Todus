import WidgetKit
import SwiftUI

struct TasksWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: TaskWidgetSnapshot?
}

struct TasksTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TasksWidgetEntry {
        TasksWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TasksWidgetEntry) -> Void) {
        if context.isPreview {
            completion(TasksWidgetEntry(date: Date(), snapshot: .placeholder))
            return
        }
        let store = WidgetSnapshotStore.shared.readSnapshot()
        let entry = TasksWidgetEntry(date: Date(), snapshot: store?.tasks ?? .placeholder)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TasksWidgetEntry>) -> Void) {
        let store = WidgetSnapshotStore.shared.readSnapshot()
        let snapshot = store?.tasks
        
        let currentDate = Date()
        let entry = TasksWidgetEntry(date: currentDate, snapshot: snapshot)
        
        // Refresh every hour
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate) ?? currentDate.addingTimeInterval(3600)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

extension TaskWidgetSnapshot {
    static var placeholder: TaskWidgetSnapshot {
        TaskWidgetSnapshot(
            todayProgress: 0.6,
            topTasks: [
                TaskInfo(id: "1", title: "Review PRs", isOverdue: false, isUrgent: true),
                TaskInfo(id: "2", title: "Update documentation", isOverdue: true, isUrgent: false),
                TaskInfo(id: "3", title: "Weekly planning", isOverdue: false, isUrgent: false)
            ],
            overdueCount: 1
        )
    }
}

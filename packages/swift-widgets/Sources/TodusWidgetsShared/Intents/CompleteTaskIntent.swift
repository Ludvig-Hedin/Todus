import Foundation
import AppIntents
import WidgetKit

struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Task"
    static let description = IntentDescription("Marks a task as completed.")

    @Parameter(title: "Task ID")
    var taskId: String

    init() {}

    init(taskId: String) {
        self.taskId = taskId
    }

    func perform() async throws -> some IntentResult {
        // Since we are using SwiftData in the main app, and AppIntents run in the extension,
        // AppIntents run in the widget extension and can't touch the main app's
        // SwiftData store, so we hand the completion off via the App Group: queue
        // the id for the main app to apply + sync, and optimistically drop it from
        // the snapshot so the widget reflects completion immediately.
        let store = WidgetSnapshotStore.shared
        store.addPendingCompletion(taskId)
        store.updateSnapshot { snapshot in
            guard let tasks = snapshot.tasks else { return }
            let remaining = tasks.topTasks.filter { $0.id != taskId }
            guard remaining.count != tasks.topTasks.count else { return }
            snapshot.tasks = TaskWidgetSnapshot(
                todayProgress: tasks.todayProgress,
                topTasks: remaining,
                overdueCount: tasks.overdueCount
            )
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

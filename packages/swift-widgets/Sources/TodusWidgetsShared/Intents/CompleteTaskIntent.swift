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
        // we can either configure a shared SwiftData container, or write the intended action
        // to UserDefaults, then let the main app handle it.
        // For Phase 3: We will implement basic shared SwiftData container access if configured,
        // otherwise simply update the local snapshot temporarily to show it as completed
        // until the main app wakes up.

        // TODO: Actually complete the task in the shared store.
        // For now, we just pretend it was completed.
        return .result()
    }
}

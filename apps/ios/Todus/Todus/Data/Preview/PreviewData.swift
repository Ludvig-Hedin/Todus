import Foundation
import SwiftData

enum PreviewData {
    @MainActor
    static var container: ModelContainer {
        let schema = Schema([
            TaskRecord.self,
            FolderRecord.self,
            FolderItemRecord.self
        ])

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Failed to create preview container: \(error.localizedDescription)")
        }
        let context = container.mainContext

        let inbox = FolderRecord(name: "Ops")
        let tasks = [
            TaskRecord(rawInput: "Ship onboarding copy", title: "Ship onboarding copy", status: .todo),
            TaskRecord(rawInput: "Review animation timings", title: "Review animation timings", status: .doing, folder: inbox),
            TaskRecord(rawInput: "Book dentist tomorrow 09", title: "Book dentist", status: .done, dueDate: .now.addingTimeInterval(86_400))
        ]

        context.insert(inbox)
        tasks.forEach(context.insert)
        try? context.save()
        return container
    }
}

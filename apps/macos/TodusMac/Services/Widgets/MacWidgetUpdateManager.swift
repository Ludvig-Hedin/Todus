import Foundation
import SwiftData
import WidgetKit

@MainActor
final class MacWidgetUpdateManager {
    static let shared = MacWidgetUpdateManager()
    
    private init() {}
    
    func updateWidgets(
        context: ModelContext,
        emailService: EmailService
    ) {
        // 1. Fetch Tasks
        let tasksDescriptor = FetchDescriptor<TaskRecord>(predicate: #Predicate { !$0.completed }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let allIncompleteTasks = (try? context.fetch(tasksDescriptor)) ?? []
        
        let now = Date()
        let todayStart = Calendar.current.startOfDay(for: now)
        let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart.addingTimeInterval(86400)
        
        let overdueTasks = allIncompleteTasks.filter { task in
            if let due = task.dueDate { return due < todayStart }
            return false
        }
        let urgentTasks = allIncompleteTasks.filter { $0.priority == .high }
        
        let completedTodayDescriptor = FetchDescriptor<TaskRecord>(predicate: #Predicate { task in
            task.completed && task.updatedAt >= todayStart && task.updatedAt < todayEnd
        })
        let completedToday = (try? context.fetch(completedTodayDescriptor)) ?? []
        
        let totalToday = completedToday.count + allIncompleteTasks.filter { task in
            if let due = task.dueDate {
                return due >= todayStart && due < todayEnd
            }
            return false
        }.count
        
        let progress = totalToday > 0 ? Double(completedToday.count) / Double(totalToday) : 0.0
        
        let topTasks = allIncompleteTasks.prefix(6).map {
            TaskWidgetSnapshot.TaskInfo(
                id: $0.id.uuidString,
                title: $0.title,
                isOverdue: $0.dueDate.map { $0 < todayStart } ?? false,
                isUrgent: $0.priority == .high
            )
        }
        
        let taskSnapshot = TaskWidgetSnapshot(
            todayProgress: progress,
            topTasks: Array(topTasks),
            overdueCount: overdueTasks.count
        )
        
        // 2. Fetch Emails (from cached EmailService state)
        let unreadEmails = emailService.threads.filter { $0.unread }
        let topEmails = unreadEmails.prefix(5).map { thread in
            EmailWidgetSnapshot.EmailInfo(
                id: thread.id,
                senderName: thread.from.name ?? thread.from.email,
                subject: thread.subject
            )
        }

        let emailSnapshot = EmailWidgetSnapshot(
            unreadImportantCount: unreadEmails.count,
            topEmails: Array(topEmails)
        )
        
        Task {
            let store = WidgetSnapshotStore.shared.readSnapshot() ?? WidgetDataStore()
            var newStore = store
            newStore.lastUpdated = Date()
            newStore.tasks = taskSnapshot
            newStore.email = emailSnapshot
            
            newStore.overview = DailyOverviewWidgetSnapshot(
                nextEvent: newStore.calendar?.upcomingEvents.first,
                urgentTaskCount: urgentTasks.count,
                unreadImportantEmailCount: unreadEmails.count
            )
            
            WidgetSnapshotStore.shared.writeSnapshot(newStore)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

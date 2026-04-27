import Foundation
import SwiftData
import WidgetKit

@MainActor
final class WidgetUpdateManager {
    static let shared = WidgetUpdateManager()
    
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
        guard let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart) else {
            AppLogger.shared.log("WidgetUpdateManager.updateWidgets: failed to compute todayEnd")
            return
        }
        
        let overdueTasks = allIncompleteTasks.filter { task in
            if let due = task.dueDate { return due < todayStart }
            return false
        }
        let urgentTasks = allIncompleteTasks.filter { $0.priority == .high }
        
        let completedTodayDescriptor = FetchDescriptor<TaskRecord>(
            predicate: #Predicate<TaskRecord> { task in
                task.completed && task.updatedAt >= todayStart && task.updatedAt < todayEnd
            }
        )
        let completedToday = (try? context.fetch(completedTodayDescriptor)) ?? []

        // Only count tasks due today on both sides so numerator and denominator measure the same set.
        let completedDueToday = completedToday.filter { task in
            if let due = task.dueDate { return due >= todayStart && due < todayEnd }
            return false
        }
        let incompleteDueToday = allIncompleteTasks.filter { task in
            if let due = task.dueDate { return due >= todayStart && due < todayEnd }
            return false
        }
        let totalToday = completedDueToday.count + incompleteDueToday.count
        let progress = totalToday > 0 ? Double(completedDueToday.count) / Double(totalToday) : 0.0
        
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
        
        // 2. Fetch Emails (from cached EmailService state, no blocking network call)
        let unreadThreads = emailService.threads.filter { $0.unread }
        // Gmail's IMPORTANT label is the canonical source of importance — match the widget UI's
        // "Important Emails" framing rather than counting all unread.
        let unreadImportantThreads = unreadThreads.filter { thread in
            thread.labels.contains { $0.uppercased() == "IMPORTANT" }
        }
        let topEmails = unreadThreads.prefix(5).map { thread in
            EmailWidgetSnapshot.EmailInfo(
                id: thread.id,
                senderName: thread.from.name.isEmpty ? thread.from.email : thread.from.name,
                subject: thread.subject
            )
        }

        let emailSnapshot = EmailWidgetSnapshot(
            unreadImportantCount: unreadImportantThreads.count,
            topEmails: Array(topEmails)
        )
        
        // 3. Calendar Events (we assume an async fetch or we just use EventKit directly here if needed.
        // For simplicity, we'll let the user see placeholder until we fetch it properly, or we can fetch it synchronously if possible, but EventKit requires async or blocks.
        // Actually, we can dispatch an async task for the calendar fetch)
        
        // All data is ready — apply via the atomic updateSnapshot so a concurrent
        // updateWidgets call can't read stale state and overwrite our changes.
        WidgetSnapshotStore.shared.updateSnapshot { store in
            store.lastUpdated = Date()
            store.tasks = taskSnapshot
            store.email = emailSnapshot
            store.overview = DailyOverviewWidgetSnapshot(
                nextEvent: store.calendar?.upcomingEvents.first,
                urgentTaskCount: urgentTasks.count,
                unreadImportantEmailCount: unreadImportantThreads.count
            )
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

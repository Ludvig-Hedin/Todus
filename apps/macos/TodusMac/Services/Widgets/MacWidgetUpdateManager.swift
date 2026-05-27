import Foundation
import SwiftData
import WidgetKit

@MainActor
final class MacWidgetUpdateManager {
    static let shared = MacWidgetUpdateManager()
    
    private init() {}
    
    func updateWidgets(
        context: ModelContext,
        services: MacAppServices
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
        let unreadEmails = services.emailService.threads.filter { $0.unread }
        let topEmails = unreadEmails.prefix(5).map { thread in
            EmailWidgetSnapshot.EmailInfo(
                id: thread.id,
                senderName: thread.from.name.isEmpty ? thread.from.email : thread.from.name,
                subject: thread.subject
            )
        }

        let emailSnapshot = EmailWidgetSnapshot(
            unreadImportantCount: unreadEmails.count,
            topEmails: Array(topEmails)
        )
        
        Task {
            // Calendar — upcoming events over the next 7 days. Previously never
            // written, so the Calendar widget and the Daily Overview "next event"
            // were permanently empty.
            let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now.addingTimeInterval(7 * 86400)
            let unifiedEvents = await services.unifiedCalendarService.events(
                from: now,
                to: weekEnd,
                preferences: services.calendarPreferences
            )
            let upcoming: [CalendarWidgetSnapshot.Event] = unifiedEvents
                .filter { $0.endDate >= now }
                .sorted { $0.startDate < $1.startDate }
                .prefix(8)
                .map { ev in
                    CalendarWidgetSnapshot.Event(
                        id: ev.providerEventId,
                        title: ev.title,
                        startDate: ev.startDate,
                        endDate: ev.endDate,
                        isAllDay: ev.isAllDay,
                        colorHex: Self.packColor(r: ev.colorRed, g: ev.colorGreen, b: ev.colorBlue),
                        url: URL(string: "todus://calendar")
                    )
                }
            let calendarSnapshot = CalendarWidgetSnapshot(upcomingEvents: upcoming)
            let nextEvent = upcoming.first
            let insight = Self.buildInsight(
                overdueCount: overdueTasks.count,
                urgentCount: urgentTasks.count,
                nextEvent: nextEvent,
                unreadImportant: unreadEmails.count
            )

            // Atomic transform avoids clobbering fields written by a concurrent
            // update (e.g. a widget-completion snapshot edit).
            WidgetSnapshotStore.shared.updateSnapshot { newStore in
                newStore.lastUpdated = Date()
                newStore.tasks = taskSnapshot
                newStore.email = emailSnapshot
                newStore.calendar = calendarSnapshot
                newStore.insight = insight
                newStore.overview = DailyOverviewWidgetSnapshot(
                    nextEvent: nextEvent,
                    urgentTaskCount: urgentTasks.count,
                    unreadImportantEmailCount: unreadEmails.count
                )
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private static func packColor(r: Double, g: Double, b: Double) -> UInt {
        let ri = UInt(max(0, min(255, r * 255)))
        let gi = UInt(max(0, min(255, g * 255)))
        let bi = UInt(max(0, min(255, b * 255)))
        return (ri << 16) | (gi << 8) | bi
    }

    private static func buildInsight(
        overdueCount: Int,
        urgentCount: Int,
        nextEvent: CalendarWidgetSnapshot.Event?,
        unreadImportant: Int
    ) -> SmartInsightWidgetSnapshot {
        if overdueCount > 0 {
            return SmartInsightWidgetSnapshot(
                insightText: "\(overdueCount) task\(overdueCount == 1 ? "" : "s") overdue.",
                recommendedActionText: "Review overdue tasks"
            )
        }
        if let next = nextEvent {
            let f = DateFormatter()
            f.timeStyle = .short
            f.dateStyle = .none
            return SmartInsightWidgetSnapshot(
                insightText: "Next: \(next.title) at \(f.string(from: next.startDate)).",
                recommendedActionText: nil
            )
        }
        if urgentCount > 0 {
            return SmartInsightWidgetSnapshot(
                insightText: "\(urgentCount) urgent task\(urgentCount == 1 ? "" : "s") to tackle.",
                recommendedActionText: nil
            )
        }
        if unreadImportant > 0 {
            return SmartInsightWidgetSnapshot(
                insightText: "\(unreadImportant) unread email\(unreadImportant == 1 ? "" : "s") waiting.",
                recommendedActionText: nil
            )
        }
        return SmartInsightWidgetSnapshot(insightText: "You're all caught up.", recommendedActionText: nil)
    }
}

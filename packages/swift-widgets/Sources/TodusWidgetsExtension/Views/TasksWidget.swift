import WidgetKit
import SwiftUI

struct TasksWidget: Widget {
    let kind: String = "TasksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TasksTimelineProvider()) { entry in
            TasksWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Tasks")
        .description("Keep track of your top tasks.")
        #if os(macOS)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        #else
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
        #endif
    }
}

struct TasksWidgetEntryView: View {
    var entry: TasksTimelineProvider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallTasksView(snapshot: entry.snapshot)
        case .systemMedium:
            MediumTasksView(snapshot: entry.snapshot)
        case .systemLarge:
            LargeTasksView(snapshot: entry.snapshot)
        #if !os(macOS)
        case .accessoryRectangular:
            AccessoryTasksView(snapshot: entry.snapshot)
        #endif
        default:
            MediumTasksView(snapshot: entry.snapshot)
        }
    }
}

struct SmallTasksView: View {
    let snapshot: TaskWidgetSnapshot?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tasks")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if let progress = snapshot?.todayProgress {
                    CircularProgressView(progress: progress)
                        .frame(width: 16, height: 16)
                }
            }
            
            if let tasks = snapshot?.topTasks, !tasks.isEmpty {
                ForEach(tasks.prefix(2)) { task in
                    TaskRow(task: task)
                }
            } else {
                Text("All caught up!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .containerBackground(for: .widget) {
            #if os(macOS)
            Color(NSColor.windowBackgroundColor)
            #else
            Color(UIColor.systemBackground)
            #endif
        }
        .widgetURL(URL(string: "todus://tasks"))
    }
}

struct MediumTasksView: View {
    let snapshot: TaskWidgetSnapshot?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tasks")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if let overdue = snapshot?.overdueCount, overdue > 0 {
                    Text("\(overdue) overdue")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
            
            if let tasks = snapshot?.topTasks, !tasks.isEmpty {
                ForEach(tasks.prefix(3)) { task in
                    TaskRow(task: task)
                }
            } else {
                Text("All caught up!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .containerBackground(for: .widget) {
            #if os(macOS)
            Color(NSColor.windowBackgroundColor)
            #else
            Color(UIColor.systemBackground)
            #endif
        }
        .widgetURL(URL(string: "todus://tasks"))
    }
}

struct LargeTasksView: View {
    let snapshot: TaskWidgetSnapshot?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tasks")
                    .font(.headline)
                Spacer()
                if let overdue = snapshot?.overdueCount, overdue > 0 {
                    Text("\(overdue) overdue")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            .padding(.bottom, 4)
            
            if let tasks = snapshot?.topTasks, !tasks.isEmpty {
                ForEach(tasks.prefix(6)) { task in
                    TaskRow(task: task)
                    if task.id != tasks.prefix(6).last?.id {
                        Divider()
                    }
                }
            } else {
                Text("All caught up!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .containerBackground(for: .widget) {
            #if os(macOS)
            Color(NSColor.windowBackgroundColor)
            #else
            Color(UIColor.systemBackground)
            #endif
        }
        .widgetURL(URL(string: "todus://tasks"))
    }
}

struct AccessoryTasksView: View {
    let snapshot: TaskWidgetSnapshot?
    
    var body: some View {
        VStack(alignment: .leading) {
            if let tasks = snapshot?.topTasks, let first = tasks.first {
                HStack(alignment: .top) {
                    Image(systemName: first.isOverdue ? "exclamationmark.circle" : "circle")
                    Text(first.title)
                        .font(.headline)
                        .privacySensitive()
                }
            } else {
                Text("No Tasks")
                    .font(.headline)
            }
        }
        .widgetURL(URL(string: "todus://tasks"))
    }
}

struct TaskRow: View {
    let task: TaskWidgetSnapshot.TaskInfo
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if #available(iOS 17.0, macOS 14.0, *) {
                Button(intent: CompleteTaskIntent(taskId: task.id)) {
                    Image(systemName: "circle")
                        .foregroundColor(task.isOverdue ? .red : (task.isUrgent ? .orange : .secondary))
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(task.isOverdue ? .red : (task.isUrgent ? .orange : .secondary))
                    .font(.system(size: 15))
                    .padding(.top, 1)
            }
            
            Text(task.title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(task.isOverdue ? .red : .primary)
                .lineLimit(1)
                .privacySensitive()
            
            Spacer()
        }
    }
}

struct CircularProgressView: View {
    let progress: Double
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 3)
                .opacity(0.3)
                .foregroundColor(Color.blue)
            
            Circle()
                .trim(from: 0.0, to: CGFloat(min(progress, 1.0)))
                .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .foregroundColor(Color.blue)
                .rotationEffect(Angle(degrees: 270.0))
        }
    }
}

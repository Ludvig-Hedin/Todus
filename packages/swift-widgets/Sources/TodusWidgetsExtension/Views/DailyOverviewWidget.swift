import WidgetKit
import SwiftUI

struct DailyOverviewWidget: Widget {
    let kind: String = "DailyOverviewWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyOverviewTimelineProvider()) { entry in
            DailyOverviewWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Daily Overview")
        .description("Your day at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DailyOverviewWidgetEntryView: View {
    var entry: DailyOverviewTimelineProvider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallOverviewView(snapshot: entry.snapshot)
        default:
            MediumOverviewView(snapshot: entry.snapshot)
        }
    }
}

struct SmallOverviewView: View {
    let snapshot: DailyOverviewWidgetSnapshot?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let event = snapshot?.nextEvent {
                VStack(alignment: .leading, spacing: 3) {
                    Text("NEXT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .privacySensitive()
                    Text(event.startDate, style: .time)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.blue)
                }
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("NEXT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    Text("Clear schedule")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            
            Divider()
            
            HStack {
                if let tasks = snapshot?.urgentTaskCount, tasks > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checklist")
                            .font(.caption2)
                        Text("\(tasks)")
                            .font(.caption.bold())
                    }
                    .foregroundColor(.orange)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.caption2)
                        Text("0")
                            .font(.caption.bold())
                    }
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let emails = snapshot?.unreadImportantEmailCount, emails > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "envelope.fill")
                            .font(.caption2)
                        Text("\(emails)")
                            .font(.caption.bold())
                    }
                    .foregroundColor(.blue)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "tray")
                            .font(.caption2)
                        Text("0")
                            .font(.caption.bold())
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .containerBackground(for: .widget) {
            #if os(macOS)
            Color(NSColor.windowBackgroundColor)
            #else
            Color(UIColor.systemBackground)
            #endif
        }
        .widgetURL(URL(string: "todus://today"))
    }
}

struct MediumOverviewView: View {
    let snapshot: DailyOverviewWidgetSnapshot?
    
    var body: some View {
        HStack(spacing: 0) {
            SmallOverviewView(snapshot: snapshot)
            
            Divider()
                .padding(.vertical)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("QUICK ACTIONS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.top, 16)
                    .padding(.horizontal)
                
                VStack(spacing: 8) {
                    Link(destination: URL(string: "todus://tasks")!) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.orange)
                            Text("New Task")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    Link(destination: URL(string: "mailto:")!) {
                        HStack {
                            Image(systemName: "square.and.pencil")
                                .foregroundColor(.blue)
                            Text("Compose")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
                
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .containerBackground(for: .widget) {
            #if os(macOS)
            Color(NSColor.windowBackgroundColor)
            #else
            Color(UIColor.systemBackground)
            #endif
        }
    }
}

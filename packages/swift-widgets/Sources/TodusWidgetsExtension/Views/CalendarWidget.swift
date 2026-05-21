import WidgetKit
import SwiftUI

struct CalendarWidget: Widget {
    let kind: String = "CalendarWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalendarTimelineProvider()) { entry in
            CalendarWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Upcoming Schedule")
        .description("See your next events at a glance.")
        #if os(macOS)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        #else
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
        #endif
    }
}

struct CalendarWidgetEntryView: View {
    var entry: CalendarTimelineProvider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallCalendarView(snapshot: entry.snapshot)
        case .systemMedium:
            MediumCalendarView(snapshot: entry.snapshot)
        #if !os(macOS)
        case .accessoryRectangular:
            AccessoryCalendarView(snapshot: entry.snapshot)
        case .accessoryInline:
            AccessoryInlineCalendarView(snapshot: entry.snapshot)
        #endif
        default:
            MediumCalendarView(snapshot: entry.snapshot)
        }
    }
}

struct SmallCalendarView: View {
    let snapshot: CalendarWidgetSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.red)
                Spacer()
            }
            
            if let events = snapshot?.upcomingEvents.filter({ $0.endDate > Date() }), let first = events.first {
                VStack(alignment: .leading, spacing: 3) {
                    Text(first.startDate, style: .time)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.red)
                    Text(first.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(3)
                        .privacySensitive()
                }
                .padding(.top, 4)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    VStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("Clear schedule")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .containerBackground(for: .widget) {
            #if os(macOS)
            Color(NSColor.windowBackgroundColor)
            #else
            Color(UIColor.systemBackground)
            #endif
        }
        .widgetURL(URL(string: "todus://calendar"))
    }
}

struct MediumCalendarView: View {
    let snapshot: CalendarWidgetSnapshot?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.red)
                Spacer()
            }
            
            if let events = snapshot?.upcomingEvents.filter({ $0.endDate > Date() }), !events.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(events.prefix(3)) { event in
                        HStack(alignment: .top, spacing: 8) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(hex: event.colorHex))
                                .frame(width: 4)
                                .padding(.vertical, 2)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .privacySensitive()
                                Text(event.startDate, style: .time)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    VStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.title)
                            .foregroundStyle(.tertiary)
                        Text("No upcoming events")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .containerBackground(for: .widget) {
            #if os(macOS)
            Color(NSColor.windowBackgroundColor)
            #else
            Color(UIColor.systemBackground)
            #endif
        }
        .widgetURL(URL(string: "todus://calendar"))
    }
}

struct AccessoryCalendarView: View {
    let snapshot: CalendarWidgetSnapshot?

    var body: some View {
        VStack(alignment: .leading) {
            if let events = snapshot?.upcomingEvents.filter({ $0.endDate > Date() }), let first = events.first {
                Text(first.title)
                    .font(.headline)
                    .privacySensitive()
                Text(first.startDate, style: .time)
                    .font(.caption)
            } else {
                Text("No events")
                    .font(.headline)
            }
        }
        .containerBackground(for: .widget) {}
        .widgetURL(URL(string: "todus://calendar"))
    }
}

struct AccessoryInlineCalendarView: View {
    let snapshot: CalendarWidgetSnapshot?

    var body: some View {
        Group {
            if let events = snapshot?.upcomingEvents.filter({ $0.endDate > Date() }), let first = events.first {
                Text("\(first.startDate, style: .time) \(first.title)")
                    .privacySensitive()
            } else {
                Text("No events")
            }
        }
        .containerBackground(for: .widget) {}
        .widgetURL(URL(string: "todus://calendar"))
    }
}

extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

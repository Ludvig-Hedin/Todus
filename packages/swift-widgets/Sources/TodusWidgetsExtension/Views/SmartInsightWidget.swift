import WidgetKit
import SwiftUI

struct SmartInsightWidget: Widget {
    let kind: String = "SmartInsightWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SmartInsightTimelineProvider()) { entry in
            SmartInsightWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Smart Insight")
        .description("AI-generated insights about your day.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct SmartInsightWidgetEntryView: View {
    var entry: SmartInsightTimelineProvider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallInsightView(snapshot: entry.snapshot)
        case .systemMedium:
            MediumInsightView(snapshot: entry.snapshot)
        case .systemLarge:
            LargeInsightView(snapshot: entry.snapshot)
        default:
            MediumInsightView(snapshot: entry.snapshot)
        }
    }
}

struct SmallInsightView: View {
    let snapshot: SmartInsightWidgetSnapshot?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("Insight")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.purple)
            }
            
            if let insight = snapshot?.insightText {
                Text(insight)
                    .font(.caption.weight(.medium))
                    .lineLimit(4)
                    .privacySensitive()
            } else {
                Text("Your day is looking clear!")
                    .font(.caption.weight(.medium))
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
        .widgetURL(URL(string: "todus://today"))
    }
}

struct MediumInsightView: View {
    let snapshot: SmartInsightWidgetSnapshot?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("Smart Insight")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.purple)
            }
            
            if let insight = snapshot?.insightText {
                Text(insight)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .privacySensitive()
                
                if let action = snapshot?.recommendedActionText {
                    Text(action)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .privacySensitive()
                }
            } else {
                Text("Your day is looking clear!")
                    .font(.subheadline.weight(.medium))
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
        .widgetURL(URL(string: "todus://today"))
    }
}

struct LargeInsightView: View {
    let snapshot: SmartInsightWidgetSnapshot?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundColor(.purple)
                Text("Smart Insight")
                    .font(.headline)
            }
            
            if let insight = snapshot?.insightText {
                Text(insight)
                    .font(.body.weight(.medium))
                    .privacySensitive()
                
                if let action = snapshot?.recommendedActionText {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RECOMMENDATION")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.purple.opacity(0.8))
                        Text(action)
                            .font(.subheadline.weight(.medium))
                            .privacySensitive()
                    }
                    .padding()
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(8)
                }
            } else {
                Text("Your day is looking clear!")
                    .font(.body.weight(.medium))
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
        .widgetURL(URL(string: "todus://today"))
    }
}

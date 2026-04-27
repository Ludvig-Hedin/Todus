import SwiftUI

/// A positioned event block for the calendar time grid.
/// Apple Calendar style: filled colored background with white text, rounded pill shape.
/// Designed to be absolutely positioned inside a ZStack by the parent grid.
struct CalendarEventBlockView: View {
    let event: CalendarEvent
    let height: CGFloat
    var onTap: (() -> Void)? = nil

    @State private var isHovered = false

    private var eventColor: Color {
        Color(red: event.calendarColorRed, green: event.calendarColorGreen, blue: event.calendarColorBlue)
    }

    var body: some View {
        // Use Button instead of onTapGesture — Button is reliably tappable inside
        // macOS ScrollView, while onTapGesture can be swallowed by the scroll gesture recognizer.
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Title — white on colored background, Apple Calendar style
                Text(event.title)
                    .font(MacTheme.calendarEventTitleFont())
                    .foregroundStyle(.white)
                    .lineLimit(height >= 36 ? 2 : 1)

                // Time label — only when block is tall enough
                if height >= 36 {
                    Text(timeString)
                        .font(MacTheme.calendarEventTimeFont())
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: max(height, MacTheme.calendarMinEventHeight))
            .background(
                RoundedRectangle(cornerRadius: MacTheme.calendarEventRadius, style: .continuous)
                    .fill(eventColor.opacity(isHovered ? 0.95 : 0.85))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointerStyle(.link)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button {
                if let url = URL(string: "x-apple-calevent://\(event.id)") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open in Calendar", systemImage: "arrow.up.forward.app")
            }
        }
    }

    private var timeString: String {
        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}

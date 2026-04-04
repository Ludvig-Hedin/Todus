import SwiftUI

/// A positioned event block for the calendar time grid.
/// Apple Calendar style: filled colored background with white text, rounded pill shape.
/// Ported from macOS with iOS-appropriate touch targets and interactions.
struct CalendarEventBlockView: View {
    let event: CalendarEvent
    let height: CGFloat
    var onTap: (() -> Void)? = nil

    private var eventColor: Color {
        Color(red: event.calendarColorRed, green: event.calendarColorGreen, blue: event.calendarColorBlue)
    }

    private let eventRadius: CGFloat = 4
    private let minEventHeight: CGFloat = 24

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Title — white on colored background
                Text(event.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(height >= 44 ? 2 : 1)

                // Time label — only when block is tall enough
                if height >= 44 {
                    Text(timeString)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: max(height, minEventHeight))
            .background(
                RoundedRectangle(cornerRadius: eventRadius, style: .continuous)
                    .fill(eventColor.opacity(0.85))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var timeString: String {
        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}

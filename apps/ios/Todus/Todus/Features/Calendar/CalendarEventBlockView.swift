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
            // iOS HIG calls for a 44pt minimum tap target. A custom hit shape
            // keeps the visible pill at `height` while widening the hit region
            // so short events are still tappable on a thumb.
            .contentShape(HitTargetShape(minHeight: 44))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(event.title), \(timeString)")
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            Button {
                onTap?()
            } label: {
                Label("Open", systemImage: "calendar")
            }
            Button {
                UIPasteboard.general.string = event.title
            } label: {
                Label("Copy title", systemImage: "doc.on.doc")
            }
            Button {
                UIPasteboard.general.string = "\(event.title) — \(timeString)"
            } label: {
                Label("Copy event summary", systemImage: "text.quote")
            }
        }
    }

    private var timeString: String {
        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}

/// Custom hit-test shape that always reports a rectangle at least `minHeight`
/// points tall — used to enlarge tap targets without resizing the visible view.
private struct HitTargetShape: Shape {
    let minHeight: CGFloat
    func path(in rect: CGRect) -> Path {
        let height = max(rect.height, minHeight)
        // Centre the expanded hit rect vertically so the touch area grows
        // equally above and below the visible block instead of leaking only
        // into the event below it.
        let expandedRect = CGRect(
            x: rect.minX,
            y: rect.minY - (height - rect.height) / 2,
            width: rect.width,
            height: height
        )
        return Path(expandedRect)
    }
}

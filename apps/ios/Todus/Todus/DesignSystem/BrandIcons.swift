import SwiftUI

// MARK: - App Icon Container

/// Wraps a brand icon in a rounded-rectangle container that matches Apple app icon style.
struct AppIconContainer<Icon: View>: View {
    var size: CGFloat = 30
    var cornerRadiusFraction: CGFloat = 0.225   // Apple uses ~22.5% of size for icon radius
    var background: Color
    let icon: () -> Icon

    /// Artwork is drawn in a centered square. ~19% margin on each side; keeps Canvas/Gmail from bleeding past the white.
    private var innerContentSide: CGFloat { size * 0.62 }

    var body: some View {
        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: size * cornerRadiusFraction, style: .continuous)
                .fill(background)
                .frame(width: size, height: size)

            icon()
                .frame(width: innerContentSide, height: innerContentSide, alignment: .center)
                .clipped()
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * cornerRadiusFraction, style: .continuous))
        // Shadow applied AFTER clipShape so it is not clipped — visible in light mode.
        .shadow(color: .black.opacity(0.16), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Gmail

/// Gmail logo recreated from the official SVG (viewBox "52 42 88 66").
/// Five filled paths form the Gmail M-envelope: blue, green, yellow, red, dark-red.
struct GmailLogo: View {
    var body: some View {
        Canvas { ctx, size in
            // Map SVG viewBox 52 42 88 66 → canvas size
            let vbX: Double = 52, vbY: Double = 42, vbW: Double = 88, vbH: Double = 66
            func c(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: (x - vbX) / vbW * size.width,
                        y: (y - vbY) / vbH * size.height)
            }

            // Blue — left panel
            var blue = Path()
            blue.move(to: c(58, 108))
            blue.addLine(to: c(72, 108))
            blue.addLine(to: c(72, 74))
            blue.addLine(to: c(52, 59))
            blue.addLine(to: c(52, 102))
            blue.addCurve(to: c(58, 108),
                          control1: c(52, 105.32),
                          control2: c(54.69, 108))
            ctx.fill(blue, with: .color(Color(red: 0.259, green: 0.522, blue: 0.957)))

            // Green — right panel
            var green = Path()
            green.move(to: c(120, 108))
            green.addLine(to: c(134, 108))
            green.addCurve(to: c(140, 102),
                           control1: c(137.32, 108),
                           control2: c(140, 105.31))
            green.addLine(to: c(140, 59))
            green.addLine(to: c(120, 74))
            green.closeSubpath()
            ctx.fill(green, with: .color(Color(red: 0.204, green: 0.659, blue: 0.325)))

            // Yellow — right shoulder
            var yellow = Path()
            yellow.move(to: c(120, 48))
            yellow.addLine(to: c(120, 74))
            yellow.addLine(to: c(140, 59))
            yellow.addLine(to: c(140, 51))
            yellow.addCurve(to: c(125.6, 43.8),
                            control1: c(140, 43.58),
                            control2: c(131.53, 39.35))
            yellow.closeSubpath()
            ctx.fill(yellow, with: .color(Color(red: 0.984, green: 0.737, blue: 0.016)))

            // Red — M envelope body
            var red = Path()
            red.move(to: c(72, 74))
            red.addLine(to: c(72, 48))
            red.addLine(to: c(96, 66))
            red.addLine(to: c(120, 48))
            red.addLine(to: c(120, 74))
            red.addLine(to: c(96, 92))
            red.closeSubpath()
            ctx.fill(red, with: .color(Color(red: 0.918, green: 0.263, blue: 0.208)))

            // Dark red — left shoulder
            var darkRed = Path()
            darkRed.move(to: c(52, 51))
            darkRed.addLine(to: c(52, 59))
            darkRed.addLine(to: c(72, 74))
            darkRed.addLine(to: c(72, 48))
            darkRed.addLine(to: c(66.4, 43.8))
            darkRed.addCurve(to: c(52, 51),
                             control1: c(60.46, 39.35),
                             control2: c(52, 43.58))
            ctx.fill(darkRed, with: .color(Color(red: 0.773, green: 0.133, blue: 0.122)))
        }
        .aspectRatio(88 / 66, contentMode: .fit)
    }
}

struct GmailIconView: View {
    var size: CGFloat = 30
    var body: some View {
        AppIconContainer(size: size, background: .white) {
            GmailLogo()
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Apple Calendar

/// Full-bleed iOS Calendar icon: red weekday strip at top, white body with large day number.
/// Rendered edge-to-edge so the red stripe fills the rounded container correctly.
struct AppleCalendarLogo: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let headerH = h * 0.295

            VStack(spacing: 0) {
                // Red header — iOS system red
                ZStack {
                    Color(red: 1.0, green: 0.231, blue: 0.188)
                    Text("MON")
                        .font(.system(size: w * 0.215, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(height: headerH)

                // White body with day number
                ZStack {
                    Color.white
                    Text("12")
                        .font(.system(size: h * 0.50, weight: .light, design: .rounded))
                        .foregroundStyle(Color(red: 0.10, green: 0.10, blue: 0.12))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct AppleCalendarIconView: View {
    var size: CGFloat = 30
    private var cr: CGFloat { size * 0.225 }

    var body: some View {
        // Full-bleed: Calendar's red stripe must reach the rounded edges, so we skip
        // AppIconContainer (which insets the artwork to 62%) and clip directly.
        AppleCalendarLogo()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cr, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 3, x: 0, y: 1)
            .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Apple Reminders

/// Apple Reminders icon — three rows of (colored radio ring) + (gray pill line).
/// Drawn with proportional Canvas coordinates so it looks correct at any icon size.
/// The previous 1024×1024 coordinate approach scaled rings to ~0.2 px at 36 pt, making them invisible.
struct AppleRemindersLogo: View {
    private let dotColors: [Color] = [
        Color(red: 0.0,  green: 0.478, blue: 1.0),   // blue
        Color(red: 1.0,  green: 0.231, blue: 0.188),  // red
        Color(red: 1.0,  green: 0.584, blue: 0.0),    // orange
    ]

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let rowH = h / 3.0

            // Proportional geometry — all values relative to canvas size.
            let dotR  = w * 0.135          // outer radius of each radio circle
            let ringW = dotR * 0.40        // visible ring band width
            let innerR = dotR - ringW      // inner (white) radius
            let dotCx = w * 0.205          // x-center of the circles column
            let lineX = w * 0.375          // line start x
            let lineW = w * 0.560          // line width
            let lineH = h * 0.052          // line height (pill height)
            let lineGray = Color(red: 0.76, green: 0.76, blue: 0.78)

            for i in 0..<3 {
                let cy = rowH * (Double(i) + 0.5)

                // Colored outer disc
                let outerRect = CGRect(x: dotCx - dotR, y: cy - dotR,
                                       width: dotR * 2, height: dotR * 2)
                ctx.fill(Path(ellipseIn: outerRect), with: .color(dotColors[i]))

                // White inner disc — creates the radio-ring effect
                let innerRect = CGRect(x: dotCx - innerR, y: cy - innerR,
                                       width: innerR * 2, height: innerR * 2)
                ctx.fill(Path(ellipseIn: innerRect), with: .color(.white))

                // Gray pill line
                let lineRect = CGRect(x: lineX, y: cy - lineH / 2, width: lineW, height: lineH)
                let pill = Path(roundedRect: lineRect,
                                cornerSize: CGSize(width: lineH / 2, height: lineH / 2))
                ctx.fill(pill, with: .color(lineGray))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct AppleRemindersIconView: View {
    var size: CGFloat = 30
    private var cr: CGFloat { size * 0.225 }

    var body: some View {
        ZStack {
            Color.white
            AppleRemindersLogo()
                .frame(width: size * 0.76, height: size * 0.76)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cr, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 3, x: 0, y: 1)
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Google Meet

struct GoogleMeetIconView: View {
    var size: CGFloat = 30
    var body: some View {
        AppIconContainer(size: size, background: .white) {
            Image(systemName: "video.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Color(red: 0.0, green: 0.55, blue: 0.27))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Notes

struct NotesIconView: View {
    var size: CGFloat = 30
    var body: some View {
        AppIconContainer(size: size, background: .white) {
            Image(systemName: "note.text")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.20))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Document

struct DocumentIconView: View {
    var size: CGFloat = 30
    var body: some View {
        AppIconContainer(size: size, background: Color(red: 0.13, green: 0.46, blue: 0.95)) {
            Image(systemName: "doc.text.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.white)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Todus chat

struct TodusChatIconView: View {
    var size: CGFloat = 30
    var body: some View {
        AppIconContainer(size: size, background: .white) {
            Image(systemName: "bubble.left.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.primary)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Memory

struct MemoryIconView: View {
    var size: CGFloat = 30
    var body: some View {
        AppIconContainer(size: size, background: .white) {
            Image(systemName: "brain.head.profile")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Color.purple)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Company / generic org

struct CompanyIconView: View {
    var size: CGFloat = 30
    var body: some View {
        AppIconContainer(size: size, background: .white) {
            Image(systemName: "building.2.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Website (favicon-backed)

/// Renders a favicon for `host` (via Google's S2 service) wrapped in the
/// standard icon container. Falls back to a globe glyph while loading or
/// when no host is supplied.
struct WebsiteIconView: View {
    var size: CGFloat = 30
    var host: String?

    var body: some View {
        AppIconContainer(size: size, background: .white) {
            Group {
                if let host, let url = faviconURL(host) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        case .empty, .failure:
                            Image(systemName: "globe")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.secondary)
                        @unknown default:
                            Image(systemName: "globe")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Image(systemName: "globe")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func faviconURL(_ host: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/s2/favicons")
        components?.queryItems = [
            URLQueryItem(name: "domain", value: host),
            URLQueryItem(name: "sz", value: "64")
        ]
        return components?.url
    }
}

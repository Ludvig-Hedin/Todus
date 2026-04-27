import SwiftUI

// MARK: - App Icon Container

/// Wraps a brand icon in a rounded-rectangle container that matches Apple app icon style.
/// Ported from iOS BrandIcons.swift — uses NSColor-compatible colors.
struct AppIconContainer<Icon: View>: View {
    var size: CGFloat = 26
    var cornerRadiusFraction: CGFloat = 0.225
    var background: Color
    let icon: () -> Icon

    private var innerContentSide: CGFloat { size * 0.62 }

    var body: some View {
        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: size * cornerRadiusFraction, style: .continuous)
                .fill(background)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.1), radius: 1.5, x: 0, y: 0.5)

            icon()
                .frame(width: innerContentSide, height: innerContentSide, alignment: .center)
                .clipped()
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * cornerRadiusFraction, style: .continuous))
    }
}

// MARK: - Gmail

/// Gmail logo recreated from the official SVG (viewBox "52 42 88 66").
struct GmailLogo: View {
    var body: some View {
        Canvas { ctx, size in
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
    var size: CGFloat = 26
    var body: some View {
        AppIconContainer(size: size, background: .white) {
            GmailLogo()
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Apple Calendar

/// Matches iOS `AppleCalendarLogo`: `Path(SVG d)` is unreliable, so we use layout-based art
/// (red strip + “MON” + “12”) so the icon is never an empty `Canvas` on the white tile.
struct AppleCalendarLogo: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let headerH = h * 0.30

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: w * 0.10, style: .continuous)
                    .fill(Color.white)

                VStack(spacing: 0) {
                    ZStack {
                        Color.red
                        Text("MON")
                            .font(.system(size: w * 0.18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .frame(height: headerH)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: w * 0.10,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: w * 0.10,
                            style: .continuous
                        )
                    )

                    Spacer(minLength: 0)
                    Text("12")
                        .font(.system(size: w * 0.46, weight: .thin, design: .rounded))
                        .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

struct AppleCalendarIconView: View {
    var size: CGFloat = 26
    var body: some View {
        AppIconContainer(size: size, background: .white) {
            AppleCalendarLogo()
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Apple Reminders

/// Reminders light icon — same 1024×1024 geometry as iOS `BrandIcons` / official SVG.
private struct AppleRemindersIconArtwork {
    fileprivate static let lineGray = Color(red: 0.82, green: 0.82, blue: 0.84)
    fileprivate static let blue = Color(red: 0, green: 0.478, blue: 1)
    fileprivate static let red = Color(red: 1, green: 0.231, blue: 0.188)
    fileprivate static let orange = Color(red: 1, green: 0.584, blue: 0)
    fileprivate static let lineY: [CGFloat] = [248, 503, 758]
    fileprivate static let lineRect = CGRect(x: 375, y: 0, width: 530, height: 17)
    fileprivate static let lineCorner: CGFloat = 8.5
    fileprivate static let dotCenters: [(x: CGFloat, y: CGFloat, color: Color)] = [
        (193, 257, blue),
        (193, 512, red),
        (193, 767, orange),
    ]
    fileprivate static let outerR: CGFloat = 68
    fileprivate static let innerR: CGFloat = 59
}

struct AppleRemindersLogo: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 1024
            let tx = (size.width - 1024 * s) * 0.5
            let ty = (size.height - 1024 * s) * 0.5

            func o(_ r: CGRect) -> CGRect {
                CGRect(
                    x: tx + r.origin.x * s,
                    y: ty + r.origin.y * s,
                    width: r.size.width * s,
                    height: r.size.height * s
                )
            }

            for y in AppleRemindersIconArtwork.lineY {
                let p = Path(
                    roundedRect: o(CGRect(x: AppleRemindersIconArtwork.lineRect.minX, y: y, width: AppleRemindersIconArtwork.lineRect.width, height: AppleRemindersIconArtwork.lineRect.height)),
                    cornerSize: CGSize(width: AppleRemindersIconArtwork.lineCorner * s, height: AppleRemindersIconArtwork.lineCorner * s),
                    style: .continuous
                )
                context.fill(p, with: .color(AppleRemindersIconArtwork.lineGray))
            }

            for dot in AppleRemindersIconArtwork.dotCenters {
                let outer = o(CGRect(
                    x: dot.x - AppleRemindersIconArtwork.outerR,
                    y: dot.y - AppleRemindersIconArtwork.outerR,
                    width: AppleRemindersIconArtwork.outerR * 2,
                    height: AppleRemindersIconArtwork.outerR * 2
                ))
                context.fill(Path(ellipseIn: outer), with: .color(dot.color))
                let inner = o(CGRect(
                    x: dot.x - AppleRemindersIconArtwork.innerR,
                    y: dot.y - AppleRemindersIconArtwork.innerR,
                    width: AppleRemindersIconArtwork.innerR * 2,
                    height: AppleRemindersIconArtwork.innerR * 2
                ))
                context.fill(Path(ellipseIn: inner), with: .color(.white))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct AppleRemindersIconView: View {
    var size: CGFloat = 26
    var body: some View {
        AppIconContainer(size: size, background: .white) {
            AppleRemindersLogo()
        }
        .frame(width: size, height: size)
        .aspectRatio(contentMode: .fit)
    }
}

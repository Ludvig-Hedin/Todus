import SwiftUI

// MARK: - App Icon Container

/// Wraps a brand icon in a rounded-rectangle container that matches Apple app icon style.
struct AppIconContainer<Icon: View>: View {
    var size: CGFloat = 30
    var cornerRadiusFraction: CGFloat = 0.225   // Apple uses ~22.5% of size for icon radius
    var background: Color
    let icon: () -> Icon

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * cornerRadiusFraction, style: .continuous)
                .fill(background)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)

            icon()
                // 0.62 gives ~19% breathing room on each side — icons feel airy, not cramped
                .frame(width: size * 0.62)
                .aspectRatio(contentMode: .fit)
        }
        .frame(width: size, height: size)
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

/// Apple Calendar app icon — simplified recreation of the white/red calendar icon.
struct AppleCalendarLogo: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let headerH = h * 0.30

            ZStack(alignment: .top) {
                // White body
                RoundedRectangle(cornerRadius: w * 0.10, style: .continuous)
                    .fill(Color.white)

                VStack(spacing: 0) {
                    // Red header with weekday
                    ZStack {
                        Color.red
                        Text("MON")
                            .font(.system(size: w * 0.18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .frame(height: headerH)
                    .clipShape(
                        .rect(
                            topLeadingRadius: w * 0.10,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: w * 0.10,
                            style: .continuous
                        )
                    )

                    // Date number
                    Spacer()
                    Text("12")
                        .font(.system(size: w * 0.46, weight: .thin, design: .rounded))
                        .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
                    Spacer()
                }
            }
        }
    }
}

struct AppleCalendarIconView: View {
    var size: CGFloat = 30
    var body: some View {
        AppleCalendarLogo()
            .frame(width: size)
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Apple Reminders

/// Apple Reminders icon — three coloured circle indicators with grey text lines.
/// Background is transparent — AppIconContainer provides the white rounded rect.
struct AppleRemindersLogo: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let dotR = w * 0.12
            let lineH = dotR * 0.32
            // rowSpacing must satisfy: 3*(2*dotR) + 2*rowSpacing ≤ ~0.85*h
            // 0.72h + 2*rowSpacing ≤ 0.85h → rowSpacing ≤ 0.065h
            // Using 0.11h gives visible gap while all 3 rows fit comfortably.
            let rowSpacing = h * 0.11

            VStack(spacing: 0) {
                Spacer()
                reminderRow(dotColor: .blue, dotRadius: dotR, lineH: lineH, width: w)
                Spacer().frame(height: rowSpacing)
                reminderRow(dotColor: .red, dotRadius: dotR, lineH: lineH, width: w)
                Spacer().frame(height: rowSpacing)
                reminderRow(dotColor: .orange, dotRadius: dotR, lineH: lineH, width: w)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func reminderRow(dotColor: Color, dotRadius: CGFloat, lineH: CGFloat, width: CGFloat) -> some View {
        HStack(spacing: width * 0.10) {
            Circle()
                .fill(dotColor)
                .frame(width: dotRadius * 2, height: dotRadius * 2)
            Capsule()
                .fill(Color(UIColor.systemGray3))
                .frame(width: width * 0.50, height: lineH)
            Spacer()
        }
        .padding(.horizontal, width * 0.10)
    }
}

struct AppleRemindersIconView: View {
    var size: CGFloat = 30
    var body: some View {
        // Use AppIconContainer so the logo gets proper padding and the white rounded-rect
        // background matches the GmailIconView style — no longer stretches to fill its frame.
        AppIconContainer(size: size, background: .white) {
            AppleRemindersLogo()
        }
        .frame(width: size)
        .aspectRatio(contentMode: .fit)
    }
}

import SwiftUI

/// A polished card surface that renders a folder with its color, icon, total
/// item count, recent-item previews, and a per-type breakdown footer.
///
/// Two layouts:
/// - `.horizontal` — fixed-width tile for use in a horizontal scroller (Home)
/// - `.grid` — flexible-width cell for `LazyVGrid` (Tasks page, FolderManagementView)
struct FolderCardView: View {
    enum Layout {
        case horizontal
        case grid
    }

    let folder: FolderRecord
    var layout: Layout = .horizontal

    private var accent: Color {
        if let hex = folder.colorHex, !hex.isEmpty {
            return Color(hex: hex)
        }
        return AppTheme.subtleText
    }

    private var iconName: String {
        folder.iconName ?? "folder.fill"
    }

    private var width: CGFloat? {
        switch layout {
        case .horizontal: return 220
        case .grid: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            preview
            footer
        }
        .padding(16)
        .frame(width: width, alignment: .leading)
        .frame(minHeight: 156, alignment: .topLeading)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .strokeBorder(AppTheme.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .shadow(color: AppTheme.shadowColor, radius: 12, x: 0, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }

            Text(folder.name)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text("\(folder.cachedItemCount)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(accent.opacity(0.14))
                )
                .foregroundStyle(accent)
        }
    }

    @ViewBuilder
    private var preview: some View {
        let items = Array(folder.recentItems.prefix(3))
        if items.isEmpty {
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Text("Empty folder")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.mutedText)
                    Text("Tap to add items")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.mutedText.opacity(0.8))
                }
                Spacer()
            }
            .padding(.vertical, 14)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Image(systemName: iconForType(item.type))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.mutedText)
                            .frame(width: 14, alignment: .center)
                        Text(item.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        let breakdown = folder.breakdown
        let chips = chipLabels(for: breakdown)
        if !chips.isEmpty {
            HStack(spacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    Text(chip)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(AppTheme.surfaceSecondary)
                        )
                        .foregroundStyle(AppTheme.subtleText)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var background: some View {
        ZStack {
            AppTheme.surfacePrimary
            LinearGradient(
                colors: [accent.opacity(0.10), accent.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func iconForType(_ type: String) -> String {
        switch type {
        case "task": return "checklist"
        case "chat": return "bubble.left.fill"
        case "email": return "envelope.fill"
        case "event": return "calendar"
        case "doc": return "doc.text"
        default: return "circle.fill"
        }
    }

    private func chipLabels(for breakdown: FolderTypeBreakdown) -> [String] {
        var out: [String] = []
        if breakdown.tasks > 0 { out.append("\(breakdown.tasks) task\(breakdown.tasks == 1 ? "" : "s")") }
        if breakdown.emails > 0 { out.append("\(breakdown.emails) email\(breakdown.emails == 1 ? "" : "s")") }
        if breakdown.chats > 0 { out.append("\(breakdown.chats) chat\(breakdown.chats == 1 ? "" : "s")") }
        if breakdown.events > 0 { out.append("\(breakdown.events) event\(breakdown.events == 1 ? "" : "s")") }
        if breakdown.docs > 0 { out.append("\(breakdown.docs) doc\(breakdown.docs == 1 ? "" : "s")") }
        return out
    }
}

/// Empty placeholder card that opens the create-folder sheet on tap.
/// Matches `FolderCardView`'s footprint so it sits naturally at the end of
/// horizontal scrollers and grid layouts.
struct NewFolderCard: View {
    var layout: FolderCardView.Layout = .horizontal
    var action: () -> Void

    private var width: CGFloat? {
        switch layout {
        case .horizontal: return 220
        case .grid: return nil
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(AppTheme.surfaceSecondary)
                        .frame(width: 40, height: 40)
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.subtleText)
                }
                Text("New folder")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.subtleText)
            }
            .frame(width: width)
            .frame(minHeight: 156)
            .frame(maxWidth: layout == .grid ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .strokeBorder(
                        AppTheme.cardBorder,
                        style: StrokeStyle(lineWidth: 1.4, dash: [5, 4])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI

/// macOS folder card. Same polished design as iOS, scaled for desktop.
struct MacFolderCardView: View {
    enum Layout { case horizontal, grid }

    let folder: FolderRecord
    var layout: Layout = .grid

    private var accent: Color {
        if let hex = folder.colorHex, let color = Color(hex: hex) {
            return color
        }
        return MacTheme.textSecondary
    }

    private var iconName: String { folder.iconName ?? "folder.fill" }

    private var width: CGFloat? {
        switch layout {
        case .horizontal: return 240
        case .grid: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            preview
            footer
        }
        .padding(14)
        .frame(width: width, alignment: .leading)
        .frame(minHeight: 152, alignment: .topLeading)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .strokeBorder(MacTheme.cardBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
            }

            Text(folder.name)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(MacTheme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text("\(folder.cachedItemCount)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(accent.opacity(0.14)))
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
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacTheme.mutedText)
                    Text("Click to add items")
                        .font(.system(size: 10))
                        .foregroundStyle(MacTheme.mutedText.opacity(0.8))
                }
                Spacer()
            }
            .padding(.vertical, 14)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items) { item in
                    HStack(spacing: 6) {
                        Image(systemName: iconForType(item.type))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MacTheme.mutedText)
                            .frame(width: 12, alignment: .center)
                        Text(item.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MacTheme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
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
            HStack(spacing: 4) {
                ForEach(chips, id: \.self) { chip in
                    Text(chip)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(MacTheme.surfaceHover))
                        .foregroundStyle(MacTheme.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var background: some View {
        ZStack {
            MacTheme.surfaceCard
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

struct MacNewFolderCard: View {
    var layout: MacFolderCardView.Layout = .grid
    var action: () -> Void

    private var width: CGFloat? {
        switch layout {
        case .horizontal: return 240
        case .grid: return nil
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(MacTheme.surfaceHover)
                        .frame(width: 36, height: 36)
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MacTheme.textSecondary)
                }
                Text("New folder")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(MacTheme.textSecondary)
            }
            .frame(width: width)
            .frame(minHeight: 152)
            .frame(maxWidth: layout == .grid ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .strokeBorder(MacTheme.cardBorder, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            )
            .contentShape(RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        // Match the rest of the app's clickable affordances — the new-folder
        // card was previously indistinguishable from a static dashed rectangle.
        .macClickablePointer()
    }
}

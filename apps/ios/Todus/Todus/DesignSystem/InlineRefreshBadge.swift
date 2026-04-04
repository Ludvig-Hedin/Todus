import SwiftUI

struct InlineRefreshBadge: View {
    var label: String = "Updating"

    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)

            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.mutedText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(AppTheme.surfaceSecondary, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 0.8)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

import SwiftUI

/// One row in the Design System viewer.
///
/// Each row presents the token name in monospaced 13pt, a sample (color
/// swatch, a typography snippet, a radius preview, etc.), a short value string
/// (hex, point value, RGB triple), and an optional disclosure that expands to
/// a code snippet showing how to use the token in Swift.
///
/// Kept as a thin helper instead of a heavy reusable component because the
/// viewer is dogfood-only — every section in the page composes a handful of
/// these rows next to bespoke previews.
struct DSTokenRow<Sample: View>: View {
    let name: String
    let value: String
    let codeSnippet: String?
    @ViewBuilder let sample: () -> Sample

    @State private var isExpanded = false

    init(
        name: String,
        value: String,
        codeSnippet: String? = nil,
        @ViewBuilder sample: @escaping () -> Sample
    ) {
        self.name = name
        self.value = value
        self.codeSnippet = codeSnippet
        self.sample = sample
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                sample()
                    .frame(width: 56, height: 36, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(value)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if codeSnippet != nil {
                    Button {
                        withAnimation(AppTheme.Motion.fast) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? "Hide code snippet" : "Show code snippet")
                }
            }

            if let codeSnippet, isExpanded {
                Text(codeSnippet)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                            .fill(AppTheme.sheetCardFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 0.5)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 2)
    }
}

/// "How to change" callout block — surfaces the source-of-truth file plus the
/// approximate line range so future contributors can find where to edit the
/// token. Reused across every section in `DesignSystemView`.
struct DSHowToChangeNote: View {
    let path: String
    let lineRange: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("How to change").font(.system(size: 13, weight: .semibold))
            } icon: {
                Image(systemName: "wrench.adjustable")
            }
            Text("Edit ") + Text(path).font(.system(size: 12, design: .monospaced)) + Text(" (\(lineRange)).")
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                .fill(AppTheme.sheetCardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 0.5)
        )
    }
}

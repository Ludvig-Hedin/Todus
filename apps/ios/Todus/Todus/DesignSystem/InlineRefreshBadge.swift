import SwiftUI

struct InlineRefreshBadge: View {
    /// Retained as a no-op argument so existing call sites compile, and as the VoiceOver
    /// label. The visible badge is spinner-only — the previous "Updating" text read as
    /// stuck-state noise to users while a background refresh was in flight.
    var label: String = "Updating"
    /// Optional entity name so VoiceOver gets context ("Updating tasks" / "Updating mail")
    /// instead of a bare "Updating". Defaults to "items" so existing callers stay
    /// unchanged but the announcement is still grammatical.
    var entity: String

    init(label: String = "Updating", entity: String = "items") {
        self.label = label
        self.entity = entity
    }

    var body: some View {
        ButtonInlineProgressView(tint: .secondary, side: AppTheme.Metrics.compactInlineSpinner)
            .padding(6)
            .background(AppTheme.surfaceSecondary, in: Circle())
            .overlay(Circle().stroke(AppTheme.cardBorder, lineWidth: 0.8))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label) \(entity)")
    }
}

import SwiftUI

struct AssistantButton: View {
    let action: () -> Void

    @State private var isHovered = false

    /// Matches iOS app gradient: linear-gradient(151deg, #00AAF5, #EF00C2, #FF0038, #F99F00)
    private var aiGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0x00/255, green: 0xAA/255, blue: 0xF5/255), // #00AAF5
                Color(red: 0xEF/255, green: 0x00/255, blue: 0xC2/255), // #EF00C2
                Color(red: 0xFF/255, green: 0x00/255, blue: 0x38/255), // #FF0038
                Color(red: 0xF9/255, green: 0x9F/255, blue: 0x00/255), // #F99F00
            ],
            startPoint: UnitPoint(x: 0.3, y: 0),
            endPoint: UnitPoint(x: 0.7, y: 1)
        )
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "lasso.badge.sparkles")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(aiGradient)

                Text("Assistant")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.55))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: Color.primary.opacity(0.06), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointerStyle(.link)
        .opacity(isHovered ? 1.0 : 0.85)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .help("AI Assistant")
    }
}

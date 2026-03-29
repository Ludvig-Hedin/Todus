import SwiftUI

struct AssistantButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.23, green: 0.57, blue: 1.0), Color(red: 0.95, green: 0.28, blue: 0.55), Color(red: 1.0, green: 0.58, blue: 0.14)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Assistant")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.55))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }
}

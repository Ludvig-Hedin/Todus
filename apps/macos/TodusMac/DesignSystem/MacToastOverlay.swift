import SwiftUI

/// Lightweight transient toast for surfacing the result of an async assistant
/// action on macOS (e.g. "Task created.", "Could not generate a draft.").
///
/// Use via the `.macToast(_:)` modifier on any container view. The toast
/// auto-dismisses after `duration` seconds and can be dismissed with a click.
/// Mirrors the iOS `ToastOverlay` implementation so the two platforms behave
/// the same — the visual style is tuned for desktop (capsule + ultraThin
/// material with an outline).
struct MacToastMessage: Equatable, Identifiable {
    enum Style {
        case success
        case failure
        case info
    }

    let id: UUID
    let text: String
    let style: Style

    init(text: String, style: Style = .info) {
        self.id = UUID()
        self.text = text
        self.style = style
    }

    static func success(_ text: String) -> MacToastMessage { .init(text: text, style: .success) }
    static func failure(_ text: String) -> MacToastMessage { .init(text: text, style: .failure) }
    static func info(_ text: String) -> MacToastMessage { .init(text: text, style: .info) }
}

struct MacToastOverlay: View {
    let message: MacToastMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconTint)
            Text(message.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MacTheme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(MacTheme.cardBorder, lineWidth: 0.6))
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.text)
    }

    private var iconName: String {
        switch message.style {
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        case .info: return "sparkles"
        }
    }

    private var iconTint: Color {
        switch message.style {
        case .success: return .green
        case .failure: return .orange
        case .info: return .accentColor
        }
    }
}

private struct MacToastModifier: ViewModifier {
    @Binding var message: MacToastMessage?
    let duration: Double
    let bottomInset: CGFloat

    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    MacToastOverlay(message: message)
                        .padding(.bottom, bottomInset)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onTapGesture { dismiss() }
                        .id(message.id)
                }
            }
            .animation(MacTheme.Motion.spring, value: message?.id)
            .onChange(of: message?.id) { _, newId in
                dismissTask?.cancel()
                guard newId != nil else { return }
                dismissTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(duration))
                    guard !Task.isCancelled else { return }
                    dismiss()
                }
            }
    }

    private func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        message = nil
    }
}

extension View {
    /// Bind a `MacToastMessage?` and surface it as a transient capsule above
    /// the supplied bottom inset. Setting the binding to a new message
    /// replaces any in-flight toast and resets the auto-dismiss timer.
    func macToast(
        _ message: Binding<MacToastMessage?>,
        duration: Double = 3,
        bottomInset: CGFloat = 24
    ) -> some View {
        modifier(MacToastModifier(message: message, duration: duration, bottomInset: bottomInset))
    }
}

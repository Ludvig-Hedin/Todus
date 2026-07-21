import Accessibility
import SwiftUI

/// Lightweight transient toast for surfacing the result of an async action
/// (e.g. "Task created.", "Could not generate a reply draft.").
///
/// Apply to any view via the `.toast(_:)` modifier. The toast auto-dismisses
/// after `duration` seconds and can be dismissed manually by tapping. We
/// intentionally avoid a full-blown notification framework — this is just a
/// floating capsule with a fade transition.
struct ToastMessage: Equatable, Identifiable {
    enum Style {
        case success
        case failure
        case info
    }

    let id: UUID
    let text: String
    let style: Style
    /// Optional inline action (e.g. "Undo") rendered as a trailing button in
    /// the capsule. Tapping it runs `action` and dismisses the toast.
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        text: String,
        style: Style = .info,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.id = UUID()
        self.text = text
        self.style = style
        self.actionTitle = actionTitle
        self.action = action
    }

    // Closures aren't Equatable — identity is all the toast modifier compares.
    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }

    static func success(_ text: String) -> ToastMessage { .init(text: text, style: .success) }
    static func failure(_ text: String) -> ToastMessage { .init(text: text, style: .failure) }
    static func info(_ text: String) -> ToastMessage { .init(text: text, style: .info) }
}

struct ToastOverlay: View {
    let message: ToastMessage
    /// Called after the action button fires so the presenting modifier can
    /// dismiss the toast without each call site having to clear the binding.
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconTint)
            Text(message.text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let actionTitle = message.actionTitle {
                Button(actionTitle) { runAction() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(AppTheme.cardBorder, lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 6)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.text)
        // Surface the action to VoiceOver as a named custom action — the inline
        // button is merged away by `.combine`, so without this "Undo" would be
        // invisible to assistive tech.
        .accessibilityActions {
            if let actionTitle = message.actionTitle {
                Button(actionTitle) { runAction() }
            }
        }
    }

    private func runAction() {
        message.action?()
        onAction?()
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

private struct ToastModifier: ViewModifier {
    @Binding var message: ToastMessage?
    let duration: Double
    let bottomInset: CGFloat

    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    ToastOverlay(message: message, onAction: { dismiss() })
                        .padding(.bottom, bottomInset)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onTapGesture { dismiss() }
                        .id(message.id)
                }
            }
            .animation(AppTheme.Motion.slow, value: message?.id)
            .onChange(of: message?.id) { _, newId in
                dismissTask?.cancel()
                guard newId != nil else { return }
                // Announce the toast to VoiceOver — it auto-dismisses, so without
                // an announcement confirmations like "Task added to Inbox" and
                // failure toasts are silent to screen-reader users (TD-12).
                if let message {
                    AccessibilityNotification.Announcement(message.text).post()
                }
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
    /// Bind a `ToastMessage?` and surface it as a transient capsule above the
    /// supplied bottom inset. Setting the binding to a new message replaces
    /// any in-flight toast and resets the auto-dismiss timer.
    func toast(
        _ message: Binding<ToastMessage?>,
        duration: Double = 3,
        bottomInset: CGFloat = 0
    ) -> some View {
        modifier(ToastModifier(message: message, duration: duration, bottomInset: bottomInset))
    }
}

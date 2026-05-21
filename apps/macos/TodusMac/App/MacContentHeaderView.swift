import SwiftUI

// MacContentHeaderView (DISABLED)
//
// This view was the prototype for the unified content header but its action
// closures were never wired to real handlers. Kept on disk pending the new
// tabbed layout; current shell uses MacRootView's inline toolbar instead.
// Body renders EmptyView so any accidental insertion contributes nothing.
struct MacContentHeaderView: View {
    let title: String

    var body: some View {
        EmptyView()
    }

    private var _legacyBody: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            // TODO: wire to real actions
            HeaderIconButton(systemImage: "bell", help: "Notifications", accessibilityLabel: "Notifications") {}
            HeaderMenuButton()
            // TODO: wire to real actions
            HeaderIconButton(systemImage: "square.and.pencil", help: "Compose", accessibilityLabel: "Compose") {}

            // TODO: wire to real search
            Button {
                // TODO: open the global search UI
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("Search")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.7), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .pointerStyle(.link)
            .help("Search")
            .accessibilityLabel("Search")
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }
}

private struct HeaderIconButton: View {
    let systemImage: String
    let help: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(.thinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.72), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .interactiveHitTarget(expansion: 6)
        .focusEffectDisabled()
        .pointerStyle(.link)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct HeaderMenuButton: View {
    var body: some View {
        // TODO: wire to real actions
        Menu {
            Button("More Actions") {}
            Button("Share") {}
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(.thinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.72), lineWidth: 1)
                )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .interactiveHitTarget(expansion: 6)
        .focusEffectDisabled()
        .pointerStyle(.link)
        .help("More options")
        .accessibilityLabel("More header options")
    }
}

import SwiftUI

struct MacContentHeaderView: View {
    let title: String

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            HeaderIconButton(systemImage: "bell") {}
            HeaderMenuButton()
            HeaderIconButton(systemImage: "square.and.pencil") {}

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
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }
}

private struct HeaderIconButton: View {
    let systemImage: String
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
    }
}

private struct HeaderMenuButton: View {
    var body: some View {
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
    }
}

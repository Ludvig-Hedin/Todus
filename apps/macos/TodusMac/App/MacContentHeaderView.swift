import SwiftUI

struct MacContentHeaderView: View {
    let title: String

    var body: some View {
        HStack(spacing: 14) {
            HeaderPillButton(systemImage: "chevron.left") {}
            HeaderPillButton(systemImage: "chevron.right", isDisabled: true) {}

            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.9))

            Spacer(minLength: 0)

            HeaderIconButton(systemImage: "bell") {}
            HeaderMenuButton()
            HeaderIconButton(systemImage: "square.and.pencil") {}

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.46))

                Text("Search")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(red: 0.96, green: 0.96, blue: 0.96), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }
}

private struct HeaderPillButton: View {
    let systemImage: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isDisabled ? Color.black.opacity(0.25) : Color.black.opacity(0.8))
                .frame(width: 34, height: 34)
                .background(Color.white, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.black.opacity(0.04), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct HeaderIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.84))
                .frame(width: 38, height: 38)
                .background(Color.white, in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
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
                .foregroundStyle(Color.black.opacity(0.84))
                .frame(width: 38, height: 38)
                .background(Color.white, in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
    }
}

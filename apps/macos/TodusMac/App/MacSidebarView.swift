import SwiftUI

struct MacSidebarView: View {
    @Binding var selection: MacPrimarySelection
    @Binding var isEmailExpanded: Bool
    let onOpenSettings: () -> Void

    private let taskCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                SidebarItemButton(
                    title: "Home",
                    systemImage: "house",
                    isSelected: selection == .home,
                    action: { selection = .home }
                )

                SidebarItemButton(
                    title: "Tasks",
                    systemImage: "checkmark.square",
                    isSelected: selection == .tasks,
                    badgeText: String(taskCount),
                    action: { selection = .tasks }
                )

                SidebarItemButton(
                    title: "Email",
                    systemImage: "envelope",
                    isSelected: isEmailSelected,
                    trailingSystemImage: isEmailExpanded ? "chevron.down" : "chevron.right",
                    action: {
                        withAnimation(.snappy(duration: 0.18)) {
                            isEmailExpanded.toggle()
                        }
                        if !isEmailSelected {
                            selection = .email(.inbox)
                        }
                    }
                )

                if isEmailExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(EmailSection.allCases, id: \.self) { section in
                            SidebarChildItemButton(
                                title: section.title,
                                isSelected: selection == .email(section),
                                action: { selection = .email(section) }
                            )
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                SidebarItemButton(
                    title: "Calendar",
                    systemImage: "calendar",
                    isSelected: selection == .calendar,
                    action: { selection = .calendar }
                )
            }

            Spacer(minLength: 20)

            HStack(spacing: 8) {
                Menu {
                    Button("Profile") {}
                    Button("Settings") { onOpenSettings() }
                    Divider()
                    Button("Log Out", role: .destructive) {}
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.blue.opacity(0.75), .purple.opacity(0.75)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 26, height: 26)
                            .overlay(
                                Text("U")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                            )

                        Text("Username")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)

                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(sidebarBackground)
    }

    private var isEmailSelected: Bool {
        if case .email = selection {
            return true
        }

        return false
    }

    private var sidebarBackground: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(.thinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.white.opacity(0.72), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 22, x: 0, y: 14)
    }
}

private struct SidebarItemButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    var badgeText: String? = nil
    var trailingSystemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 15, weight: .medium))

                Spacer(minLength: 0)

                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.white.opacity(0.58))
                        )
                } else if let trailingSystemImage {
                    Image(systemName: trailingSystemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.black.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarChildItemButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                Text(title)
                    .font(.system(size: 15, weight: .medium))

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.9))
            .padding(.leading, 28)
            .padding(.trailing, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.black.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

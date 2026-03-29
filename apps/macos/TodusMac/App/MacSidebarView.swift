import SwiftUI

struct MacSidebarView: View {
    @Binding var selection: MacPrimarySelection
    @Binding var isEmailExpanded: Bool
    let onOpenSettings: () -> Void

    private let taskCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarChrome()
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 4) {
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
                    VStack(alignment: .leading, spacing: 3) {
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

            Spacer(minLength: 12)

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
                                    colors: [Color(red: 0.20, green: 0.55, blue: 1.0), Color(red: 0.55, green: 0.35, blue: 1.0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text("U")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                            )

                        Text("Username")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.88))
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)

                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.55))
                        .frame(width: 28, height: 28)
                        .background(Color.white, in: Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
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
            .fill(Color(red: 0.964, green: 0.961, blue: 0.955))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 8)
    }
}

private struct SidebarChrome: View {
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                WindowDot(color: Color(red: 1.0, green: 0.33, blue: 0.29))
                WindowDot(color: Color(red: 1.0, green: 0.75, blue: 0.18))
                WindowDot(color: Color(red: 0.16, green: 0.78, blue: 0.34))
            }

            Spacer(minLength: 0)

            Button(action: {}) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.78))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 24)
    }
}

private struct WindowDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
            )
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
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .regular))
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 15, weight: .medium))

                Spacer(minLength: 0)

                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.black.opacity(0.55))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? Color(red: 0.14, green: 0.50, blue: 1.0) : Color.white)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.black.opacity(0.04), lineWidth: 1)
                        )
                } else if let trailingSystemImage {
                    Image(systemName: trailingSystemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.38))
                }
            }
            .foregroundStyle(isSelected ? Color(red: 0.14, green: 0.50, blue: 1.0) : Color.black.opacity(0.84))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.white : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Color.black.opacity(0.05) : Color.clear, lineWidth: 1)
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
                    .foregroundStyle(Color.black.opacity(0.32))
                    .frame(width: 12)

                Text(title)
                    .font(.system(size: 15, weight: .medium))

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color(red: 0.14, green: 0.50, blue: 1.0) : Color.black.opacity(0.84))
            .padding(.leading, 28)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.white : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.black.opacity(0.04) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

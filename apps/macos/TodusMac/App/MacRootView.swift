import SwiftUI

enum EmailSection: String, CaseIterable, Hashable {
    case inbox
    case drafts
    case sent

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .drafts: "Drafts"
        case .sent: "Sent"
        }
    }
}

enum MacPrimarySelection: Hashable {
    case home
    case tasks
    case email(EmailSection)
    case calendar

    var title: String {
        switch self {
        case .home: "Home"
        case .tasks: "Tasks"
        case .email(let section): section.title
        case .calendar: "Calendar"
        }
    }
}

struct MacRootView: View {
    @State private var selection: MacPrimarySelection = .home
    @State private var isEmailExpanded = true
    @State private var isAssistantPresented = false
    @State private var isSettingsPresented = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 0) {
                MacSidebarView(
                    selection: $selection,
                    isEmailExpanded: $isEmailExpanded,
                    onOpenSettings: { isSettingsPresented = true }
                )
                .frame(width: 250)
                .padding(.leading, 14)
                .padding(.vertical, 12)

                VStack(spacing: 0) {
                    MacContentHeaderView(title: selection.title)

                    Divider()
                        .overlay(Color.black.opacity(0.07))

                    // Placeholder shell content until real macOS feature views are plugged in.
                    contentView(for: selection)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(detailBackground)
            }
            .padding(.trailing, 14)
            .padding(.vertical, 12)
        }
        .background(windowBackground.ignoresSafeArea())
        .preferredColorScheme(.light)
        .overlay(alignment: .bottomTrailing) {
            AssistantButton {
                isAssistantPresented = true
            }
            .padding(.trailing, 26)
            .padding(.bottom, 22)
        }
        .sheet(isPresented: $isAssistantPresented) {
            placeholderSheet(
                title: "AI Assistant",
                description: "AI Assistant (placeholder)"
            )
            .frame(minWidth: 420, minHeight: 280)
        }
        .sheet(isPresented: $isSettingsPresented) {
            placeholderSheet(
                title: "Settings",
                description: "Settings placeholder"
            )
            .frame(minWidth: 480, minHeight: 320)
        }
    }

    @ViewBuilder
    private func contentView(for selection: MacPrimarySelection) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Spacer(minLength: 8)

                switch selection {
                case .home:
                    placeholderCard(title: "Home View")
                case .tasks:
                    placeholderCard(title: "Tasks View")
                case .email(let section):
                    placeholderCard(title: "Email View (\(section.title))")
                case .calendar:
                    placeholderCard(title: "Calendar View")
                }

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, minHeight: 560, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
    }

    private func placeholderCard(title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.9))

            Text("Feature content will plug into this shell once macOS business logic is added.")
                .font(.system(size: 14))
                .foregroundStyle(Color.black.opacity(0.5))
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 24, x: 0, y: 8)
    }

    private var detailBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 28, x: 0, y: 10)
    }

    private var windowBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.972, green: 0.969, blue: 0.961),
                Color(red: 0.965, green: 0.963, blue: 0.955)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func placeholderSheet(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.9))

            Text(description)
                .font(.system(size: 14))
                .foregroundStyle(Color.black.opacity(0.55))

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }
}

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
        NavigationSplitView {
            MacSidebarView(
                selection: $selection,
                isEmailExpanded: $isEmailExpanded,
                onOpenSettings: { isSettingsPresented = true }
            )
            .navigationSplitViewColumnWidth(min: 244, ideal: 256, max: 280)
            .padding(.vertical, 8)
            .padding(.leading, 8)
            .padding(.trailing, 4)
        } detail: {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    MacContentHeaderView(title: selection.title)

                    Divider()
                        .overlay(.white.opacity(0.6))

                    // Placeholder shell content until real macOS feature views are plugged in.
                    contentView(for: selection)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(detailBackground)

                AssistantButton {
                    isAssistantPresented = true
                }
                .padding(.trailing, 24)
                .padding(.bottom, 22)
            }
            .padding(.top, 8)
            .padding(.trailing, 8)
            .padding(.bottom, 8)
        }
        .background(windowBackground.ignoresSafeArea())
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
            VStack(alignment: .leading, spacing: 16) {
                Spacer(minLength: 20)

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

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 560, alignment: .topLeading)
        }
        .scrollIndicators(.visible)
    }

    private func placeholderCard(title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Feature content will plug into this shell once macOS business logic is added.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.white.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.65), lineWidth: 1)
        )
    }

    private var detailBackground: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(.white.opacity(0.84))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(.white.opacity(0.75), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.09), radius: 36, x: 0, y: 18)
    }

    private var windowBackground: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color.white.opacity(0.94)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func placeholderSheet(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))

            Text(description)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

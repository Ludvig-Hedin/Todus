import SwiftUI

/// The root navigation shell for the unified app.
/// Custom tab bar with 4 tabs (left), AI button (right), and floating FAB above.
struct MainTabView: View {
    @Environment(AppServices.self) private var services
    @State private var selectedTab: AppTab = .home
    @State private var showCreateSheet = false
    @State private var showAIChat = false
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab content — each tab gets its own NavigationStack
            Group {
                switch selectedTab {
                case .home:
                    NavigationStack { HomeView() }
                case .tasks:
                    NavigationStack { TasksTabView() }
                case .email:
                    NavigationStack { EmailInboxView() }
                case .calendar:
                    NavigationStack { CalendarContainerView() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom tab bar with FAB overlay
            VStack(spacing: 0) {
                // FAB — floating above the right side of the tab bar
                HStack {
                    Spacer()
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(
                                Circle()
                                    .fill(AppTheme.accent)
                                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 24)
                    .padding(.bottom, 4)
                }

                // Tab bar
                tabBar
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAIChat) {
            AIChatView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: Binding(
            get: { services.showsSettings },
            set: { services.showsSettings = $0 }
        )) {
            SettingsView()
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Custom Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            // Left side: 4 primary tabs
            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedTab = tab
                        }
                    } label: {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Right side: AI button (visually separated)
            Button {
                showAIChat = true
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                    )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

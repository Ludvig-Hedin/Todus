import SwiftUI
import UIKit

/// Root navigation shell.
///
/// Layout:
///   Hidden native `TabView` for content/state preservation.
///   Visible floating `CustomTabBar` sourced from `services.tabBarTabs`.
///
/// • The create and AI actions live in the floating bar.
/// • `services.hideTabBar` hides the floating bar while detail views manage their own bottom chrome.
struct MainTabView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - State

    @SceneStorage("selectedTab") private var selectedTab: AppTab = .home
    /// Last real (non-create) tab — used as context hint for AI chat.
    @State private var previousNavigationTab: AppTab = .home

    @State private var showCreateSheet = false
    @State private var createSheetInitialType: CreateItemType = .auto
    @State private var showSessionExpiredConfirm = false
    @State private var calendarPermissionGranted = false

    @State private var homeTabId = UUID()
    @State private var tasksTabId = UUID()
    @State private var emailTabId = UUID()
    @State private var calendarTabId = UUID()
    @State private var meetingsTabId = UUID()

    @State private var sheetTab: AppTab? = nil
    @State private var showMoreSheet = false

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            tabView

            if !services.networkMonitor.isConnected {
                offlineBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if services.authService.isSessionExpired {
                sessionExpiredBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: services.networkMonitor.isConnected)
        .animation(.easeInOut(duration: 0.3), value: services.authService.isSessionExpired)
        .overlay(alignment: .bottom) {
            if !services.hideTabBar && !showCreateSheet {
                customTabBar
                    // Keep the floating bar from jumping when a keyboard appears in the
                    // underlying tabs, but do not disable keyboard-safe-area handling
                    // for sheets presented from this shell (such as AIChatView).
                    .ignoresSafeArea(.keyboard)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: services.hideTabBar)
        .animation(.easeOut(duration: 0.15), value: showCreateSheet)
    }

    // MARK: - Tab View

    private var tabView: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { HomeView() }
                .id(homeTabId)
                .tabItem { Image(systemName: selectedTab == .home ? "house.fill" : "house") }
                .tag(AppTab.home)

            NavigationStack { TasksTabView() }
                .id(tasksTabId)
                .tabItem { Image(systemName: "checklist") }
                .tag(AppTab.tasks)

            NavigationStack { EmailInboxView() }
                .id(emailTabId)
                .tabItem { Image(systemName: selectedTab == .email ? "envelope.fill" : "envelope") }
                .tag(AppTab.email)

            Group {
                if calendarPermissionGranted {
                    CalendarTabView()
                } else {
                    NavigationStack {
                        CalendarPermissionView()
                            .background(AppTheme.backgroundTop)
                    }
                }
            }
            .id(calendarTabId)
            .tabItem { Image(systemName: "calendar") }
            .tag(AppTab.calendar)

            NavigationStack { MeetingsListView() }
                .id(meetingsTabId)
                .tabItem { Image(systemName: "video") }
                .tag(AppTab.meetings)
        }
        .tint(Color(UIColor.label))
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: selectedTab) { old, new in
            guard new != old else { return }
            previousNavigationTab = new
            services.currentTab = new
            if new == .calendar {
                calendarPermissionGranted = services.calendarService.canReadEvents()
            }
        }
        .overlay {
            if showCreateSheet {
                CreateSheet(initialType: createSheetInitialType, isPresented: $showCreateSheet)
                    .zIndex(20)
            }
        }
        .sheet(isPresented: settingsBinding) {
            SettingsView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .appSheetBackground()
                .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        .sheet(isPresented: aiChatBinding, onDismiss: {
            services.showsAIChat = false
        }) {
            AIChatView(currentTab: previousNavigationTab)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
                .appSheetBackground()
                .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        .sheet(isPresented: composeEmailBinding, onDismiss: {
            services.composeEmailSeedBody = nil
            services.composeEmailSeedTo = nil
            services.composeEmailSeedSubject = nil
        }) {
            EmailComposeView(
                to: services.composeEmailSeedTo,
                subject: services.composeEmailSeedSubject,
                body: services.composeEmailSeedBody
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .appSheetBackground()
            .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        .sheet(item: $sheetTab) { tab in
            NavigationStack { sheetContent(for: tab) }
                .presentationDragIndicator(.visible)
                .appSheetBackground()
                .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        .sheet(isPresented: $showMoreSheet) {
            MoreSheetView { tab in
                showMoreSheet = false
                if services.tabBarTabs.contains(tab) {
                    selectedTab = tab
                } else {
                    services.navigateToSheet = tab
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .appSheetBackground()
            .preferredColorScheme(services.appearancePreference.colorScheme)
        }
        .onChange(of: services.navigateTo) { _, newTab in
            guard let tab = newTab else { return }
            selectedTab = tab
            services.navigateTo = nil
        }
        .onChange(of: services.tabBarTabs) { _, tabs in
            guard tabs.contains(selectedTab) || selectedTab == .meetings else { return }
            if selectedTab == .meetings && tabs.contains(.meetings) { return }
            if !tabs.contains(selectedTab) {
                selectedTab = .home
            }
        }
        .onChange(of: services.showsComposeEmail) { _, isPresented in
            if !isPresented {
                services.composeEmailSeedBody = nil
                services.composeEmailSeedTo = nil
                services.composeEmailSeedSubject = nil
            }
        }
        .onChange(of: services.requestCreateSheet) { _, requested in
            guard let requested else { return }
            createSheetInitialType = requested
            withAnimation(.snappy(duration: 0.2)) { showCreateSheet = true }
            services.requestCreateSheet = nil
        }
        .onChange(of: services.navigateToSheet) { _, tab in
            guard let tab else { return }
            if tab == .meetings && !services.tabBarTabs.contains(.meetings) {
                sheetTab = tab
            } else {
                selectedTab = tab
                sheetTab = nil
            }
            services.navigateToSheet = nil
        }
        .onAppear {
            if !visibleContentTabs.contains(selectedTab) {
                selectedTab = .home
            }
            calendarPermissionGranted = services.calendarService.canReadEvents()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                calendarPermissionGranted = services.calendarService.canReadEvents()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .todusCalendarAuthorizationDidChange)) { _ in
            calendarPermissionGranted = services.calendarService.canReadEvents()
        }
    }

    // MARK: - Floating Tab Bar

    private var customTabBar: some View {
        CustomTabBar(
            selectedTab: $selectedTab,
            tabs: services.tabBarTabs,
            onAI: {
                services.showsAIChat = true
            },
            onCreate: {
                createSheetInitialType = createType(for: selectedTab)
                withAnimation(.snappy(duration: 0.2)) { showCreateSheet = true }
            },
            onMore: {
                showMoreSheet = true
            },
            onReselect: { tab in
                resetNavigation(for: tab)
            }
        )
    }

    private var visibleContentTabs: Set<AppTab> {
        [.home, .tasks, .email, .calendar, .meetings]
    }

    // MARK: - Helpers

    private func createType(for tab: AppTab) -> CreateItemType {
        switch tab {
        case .tasks:    return .task
        case .calendar: return .event
        case .email:    return .email
        default:        return .auto
        }
    }

    private func resetNavigation(for tab: AppTab) {
        switch tab {
        case .home:
            homeTabId = UUID()
        case .tasks:
            tasksTabId = UUID()
        case .email:
            emailTabId = UUID()
        case .calendar:
            calendarTabId = UUID()
        case .meetings:
            meetingsTabId = UUID()
        case .create, .ai:
            break
        }
    }

    // MARK: - Bindings

    private var settingsBinding: Binding<Bool> {
        @Bindable var services = services
        return $services.showsSettings
    }

    private var aiChatBinding: Binding<Bool> {
        @Bindable var services = services
        return $services.showsAIChat
    }

    private var composeEmailBinding: Binding<Bool> {
        @Bindable var services = services
        return $services.showsComposeEmail
    }

    // MARK: - Sheet content (non-tab pages)

    @ViewBuilder
    private func sheetContent(for tab: AppTab) -> some View {
        switch tab {
        case .meetings:
            MeetingsListView()
        case .home, .tasks, .email, .calendar, .create:
            EmptyView()
        case .ai:
            AIChatView(currentTab: previousNavigationTab)
        }
    }

    // MARK: - Offline Banner

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 12, weight: .semibold))
            Text("No internet connection")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.red.opacity(0.85), in: Capsule())
        .padding(.top, 4)
    }

    // MARK: - Session Expired Banner

    private var sessionExpiredBanner: some View {
        Button {
            showSessionExpiredConfirm = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Session expired")
                    .font(.system(size: 13, weight: .medium))
                Text("Sign in again")
                    .font(.system(size: 13, weight: .semibold))
                    .underline()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.orange.opacity(0.9), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .confirmationDialog("Your session has expired", isPresented: $showSessionExpiredConfirm, titleVisibility: .visible) {
            Button("Sign In Again", role: .destructive) {
                services.authService.isSessionExpired = false
                services.signOut()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - FAB helpers

private extension View {
    /// Liquid Glass on iOS 26; ultraThinMaterial circle with shadow on earlier OS.
    @ViewBuilder
    func fabGlass() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: Circle())
        } else {
            self
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 6)
                .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }
}

private struct FABButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

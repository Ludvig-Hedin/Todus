import SwiftUI
import UIKit

/// Root navigation shell backed by the native iOS `TabView`.
///
/// The legacy floating `CustomTabBar` implementation remains in the codebase,
/// but it is no longer presented in the live shell.
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
    }

    // MARK: - Tab View

    private var tabView: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { HomeView() }
                .id(homeTabId)
                .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.inactiveIcon()) }
                .tag(AppTab.home)

            NavigationStack { TasksTabView() }
                .id(tasksTabId)
                .tabItem { Label(AppTab.tasks.title, systemImage: AppTab.tasks.inactiveIcon()) }
                .tag(AppTab.tasks)

            NavigationStack { EmailInboxView() }
                .id(emailTabId)
                .tabItem { Label(AppTab.email.title, systemImage: AppTab.email.inactiveIcon()) }
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
            .tabItem { Label(AppTab.calendar.title, systemImage: AppTab.calendar.inactiveIcon()) }
            .tag(AppTab.calendar)

            NavigationStack { MeetingsListView() }
                .id(meetingsTabId)
                .tabItem { Label(AppTab.meetings.title, systemImage: AppTab.meetings.inactiveIcon()) }
                .tag(AppTab.meetings)
        }
        .tint(Color(UIColor.label))
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
        .onChange(of: services.navigateTo) { _, newTab in
            guard let tab = newTab else { return }
            selectedTab = tab
            services.navigateTo = nil
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
            selectedTab = tab
            sheetTab = nil
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

    private var visibleContentTabs: Set<AppTab> {
        [.home, .tasks, .email, .calendar, .meetings]
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

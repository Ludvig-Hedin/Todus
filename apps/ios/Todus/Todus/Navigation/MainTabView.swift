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
    @State private var createTabId = UUID()
    @State private var emailTabId = UUID()
    @State private var calendarTabId = UUID()

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
        .overlay(alignment: .bottomTrailing) {
            if !services.hideTabBar && !showCreateSheet {
                aiFAB
                    .ignoresSafeArea(.keyboard)
                    .padding(.trailing, 18)
                    .padding(.bottom, 68)
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
                .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.inactiveIcon()) }
                .tag(AppTab.home)

            NavigationStack { TasksTabView() }
                .id(tasksTabId)
                .tabItem { Label(AppTab.tasks.title, systemImage: AppTab.tasks.inactiveIcon()) }
                .tag(AppTab.tasks)

            Color.clear
                .id(createTabId)
                .tabItem { Label(AppTab.create.title, systemImage: AppTab.create.inactiveIcon()) }
                .tag(AppTab.create)

            NavigationStack { EmailInboxView() }
                .id(emailTabId)
                .tabItem { Label(AppTab.email.title, systemImage: AppTab.email.inactiveIcon()) }
                .tag(AppTab.email)

            Group {
                if calendarPermissionGranted {
                    NavigationStack {
                        CalendarTabView()
                            .toolbar(.hidden, for: .navigationBar)
                    }
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
        }
        .tint(Color(UIColor.label))
        .onChange(of: selectedTab) { old, new in
            guard new != old else { return }

            if new == .create {
                createSheetInitialType = createType(for: old)
                selectedTab = old
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { showCreateSheet = true }
                return
            }

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
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
            services.composeEmailSeedAttachments = []
        }) {
            EmailComposeView(
                to: services.composeEmailSeedTo,
                subject: services.composeEmailSeedSubject,
                body: services.composeEmailSeedBody,
                seededAttachments: services.composeEmailSeedAttachments
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
            if tab == .meetings {
                sheetTab = .meetings
            } else {
                selectedTab = tab
            }
            services.navigateTo = nil
        }
        .onChange(of: services.showsComposeEmail) { _, isPresented in
            if !isPresented {
                services.composeEmailSeedBody = nil
                services.composeEmailSeedTo = nil
                services.composeEmailSeedSubject = nil
                services.composeEmailSeedAttachments = []
            }
        }
        .onChange(of: services.requestCreateSheet) { _, requested in
            guard let requested else { return }
            createSheetInitialType = requested
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { showCreateSheet = true }
            services.requestCreateSheet = nil
        }
        .onChange(of: services.navigateToSheet) { _, tab in
            guard let tab else { return }
            if tab == .meetings {
                sheetTab = .meetings
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

    private var visibleContentTabs: Set<AppTab> {
        [.home, .tasks, .email, .calendar]
    }

    private var aiFAB: some View {
        Button {
            services.showsAIChat = true
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(aiGradient)
                .frame(width: 58, height: 58)
                .contentShape(Circle())
        }
        .buttonStyle(FABButtonStyle())
        .fabGlass()
        .accessibilityLabel("Open AI Assistant")
    }

    private var aiGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0, green: 0xAA / 255.0, blue: 0xF5 / 255.0), location: 0.087),
                .init(color: Color(red: 0xEF / 255.0, green: 0, blue: 0xC2 / 255.0), location: 0.269),
                .init(color: Color(red: 1, green: 0, blue: 0x38 / 255.0), location: 0.580),
                .init(color: Color(red: 0xF9 / 255.0, green: 0x9F / 255.0, blue: 0), location: 0.913),
            ],
            startPoint: UnitPoint(x: 0.25, y: 0),
            endPoint: UnitPoint(x: 0.75, y: 1)
        )
    }

    private func createType(for tab: AppTab) -> CreateItemType {
        switch tab {
        case .tasks:    return .task
        case .calendar: return .event
        case .email:    return .email
        default:        return .auto
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
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
                .font(.caption2)
                .fontWeight(.medium)
            Text("Offline — changes will sync when reconnected")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
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
